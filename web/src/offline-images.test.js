import { it, expect, afterEach } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Script } from "node:vm";
import sharp from "sharp";
import { allowedImageUrl, packPreviews } from "../scripts/images/offline.mjs";
import { reviewHtml } from "../scripts/images/review.mjs";

const directories = [];
afterEach(async () => { for (const directory of directories.splice(0)) await rm(directory,{recursive:true,force:true}); });
async function directory() { const dir = await mkdtemp(join(tmpdir(),"twink-offline-images-")); directories.push(dir); return dir; }
const photo = { provider:"commons",id:42,thumbnailUrl:"https://thumb.wikimedia.org/example.jpg",url:"https://commons.wikimedia.org/wiki/File:Example.jpg",photographer:"Author",license:"CC0",licenseUrl:"https://creativecommons.org/publicdomain/zero/1.0/" };
const catalog = () => ({ schemaVersion:1,provider:"commons",entries:{ one:{word:"der Apfel",translation:"яблуко",candidates:[photo],selected:photo,reviewed:false} } });

it("deduplicates, embeds valid WebP thumbnails and reuses the disk cache without network", async () => {
  const input = await sharp({create:{width:800,height:600,channels:3,background:"red"}}).png().toBuffer();
  const cacheDirectory = await directory(), value = catalog(), original = structuredClone(value);
  value.entries.two = structuredClone(value.entries.one);
  let calls = 0;
  const first = await packPreviews({ catalog:value,cacheDirectory,intervalMs:0,
    fetchImpl:async()=>{ calls++; return new Response(input,{headers:{"Content-Type":"image/png"}}); } });
  expect(calls).toBe(1);
  expect(first.total).toBe(1);
  expect(first.failures).toEqual([]);
  const data = Buffer.from(first.previews["commons:42"].split(",")[1],"base64");
  const metadata = await sharp(data).metadata();
  expect(metadata.format).toBe("webp");
  expect(metadata.width).toBeLessThanOrEqual(360);
  expect(metadata.height).toBeLessThanOrEqual(240);
  expect(value.entries.one).toEqual(original.entries.one);
  const second = await packPreviews({catalog:value,cacheDirectory,intervalMs:0,fetchImpl:async()=>{throw new Error("No network");}});
  expect(second.cached).toBe(1);
  expect(second.previews).toEqual(first.previews);
});
it("rejects arbitrary hosts and credential-bearing URLs", () => {
  for (const value of ["http://thumb.wikimedia.org/a.jpg","https://attacker.test/a.jpg","https://secret@upload.wikimedia.org/a.jpg","file:///etc/passwd"]) {
    expect(()=>allowedImageUrl(value)).toThrow();
  }
  expect(allowedImageUrl(photo.thumbnailUrl).hostname).toBe("thumb.wikimedia.org");
});
it("does not follow a CDN redirect to an untrusted host", async () => {
  let calls=0;
  const result=await packPreviews({catalog:catalog(),cacheDirectory:await directory(),intervalMs:0,fetchImpl:async()=>{calls++;return new Response(null,{status:302,headers:{Location:"http://127.0.0.1/private"}});}});
  expect(calls).toBe(1);
  expect(result.failures).toHaveLength(1);
  expect(result.previews).toEqual({});
});
it("reports missing/HTML images instead of embedding an error page as a picture", async () => {
  const result=await packPreviews({catalog:catalog(),cacheDirectory:await directory(),intervalMs:0,fetchImpl:async()=>new Response("<html>error</html>",{headers:{"Content-Type":"text/html"}})});
  expect(result.failures).toHaveLength(1);
  expect(result.previews).toEqual({});
});
it("honors a CDN Retry-After and retries only once", async () => {
  const input=await sharp({create:{width:8,height:8,channels:3,background:"red"}}).png().toBuffer();
  let calls=0;const pauses=[];
  const result=await packPreviews({catalog:catalog(),cacheDirectory:await directory(),intervalMs:0,wait:async ms=>pauses.push(ms),fetchImpl:async()=>++calls===1?new Response(null,{status:429,headers:{"Retry-After":"2"}}):new Response(input,{headers:{"Content-Type":"image/png"}})});
  expect(calls).toBe(2);
  expect(pauses.some(ms=>ms>0&&ms<=2000)).toBe(true);
  expect(result.failures).toEqual([]);
});
it("produces a self-contained review script with attribution and no embedded-photo mutations", async () => {
  const input=await sharp({create:{width:8,height:8,channels:3,background:"red"}}).webp().toBuffer();
  const value=catalog(),before=structuredClone(value);
  const html=reviewHtml(value,{previews:{"commons:42":`data:image/webp;base64,${input.toString("base64")}`},offlineOnly:true});
  expect(html).toContain("data:image/webp;base64,");
  expect(html).toContain("Images from Wikimedia Commons");
  expect(value).toEqual(before);
  expect(()=>new Script(html.match(/<script>([\s\S]*?)<\/script>/u)[1])).not.toThrow();
});
