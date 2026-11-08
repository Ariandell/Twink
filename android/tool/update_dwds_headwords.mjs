import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
const source = 'https://www.dwds.de/dwds_static/wb/dwdswb-headwords.json';
const response = await fetch(source);
if (!response.ok) throw new Error('DWDS index download failed: ' + response.status);
const input = await response.json();
const fold = s => s.toLowerCase().replaceAll('ä', 'a').replaceAll('ö', 'o').replaceAll('ü', 'u')
  .replaceAll('ß', 'ss').replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
const rows = Object.entries(input).filter(([word, url]) => typeof url === 'string' && url.startsWith('https://www.dwds.de/wb/'))
  .map(([word, url]) => [fold(word), word, url.substring('https://www.dwds.de'.length)])
  .sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1].localeCompare(b[1]));
if (rows.length < 100000) throw new Error('Unexpectedly incomplete DWDS index; existing snapshot retained.');
const target = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../assets/data/dwds-headwords.json.gz');
fs.writeFileSync(target, zlib.gzipSync(Buffer.from(JSON.stringify(rows))));
console.log('DWDS headwords:', rows.length, 'source:', source);
