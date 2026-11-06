export function reviewHtml(catalog) {
  // Never interpolate API/user strings into HTML or executable JS.
  const json = JSON.stringify(catalog).replaceAll("<", "\\u003c");
  return `<!doctype html><html lang="uk"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Twink — картинки до слів</title><style>
body{font:16px system-ui;background:#101014;color:#eee;margin:24px auto;padding:0 16px;max-width:1200px}a{color:#a7d4ff}header{position:sticky;top:0;background:#101014ee;backdrop-filter:blur(16px);padding:12px 0;z-index:1}button{font:inherit;cursor:pointer;border:1px solid #777;border-radius:12px;padding:10px 16px;background:#eee;color:#111;margin:4px}article{border:1px solid #444;border-radius:18px;padding:18px;margin:18px 0}h2{margin:0 0 8px}p{white-space:pre-wrap;color:#bbb}.photos{display:flex;flex-wrap:wrap;gap:12px}.photo{width:min(100%,280px);border:2px solid transparent;border-radius:12px;padding:6px;background:#1b1b23}.photo:has(input:checked){border-color:#aaa}.photo img{width:100%;height:170px;object-fit:cover;border-radius:8px}.photo label{display:block;cursor:pointer}.photo a{display:block;font-size:13px;margin:8px 0}.status{font-size:14px;color:#ddd}.done{border-color:#60816c}
</style><header><h1>Картинки до слів</h1><a href="https://www.pexels.com" target="_blank" rel="noopener noreferrer">Photos provided by Pexels</a><p id="summary"></p><button id="save">Зберегти каталог JSON</button></header><main id="items"></main>
<script type="application/json" id="catalog">${json}</script><script>
const catalog=JSON.parse(document.getElementById('catalog').textContent), root=document.getElementById('items');
function node(tag,text,parent){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(parent)parent.append(el);return el}
function summary(){const rows=Object.values(catalog.entries);document.getElementById('summary').textContent=rows.length+' слів; перевірено '+rows.filter(x=>x.reviewed).length+'. Автоматичний вибір потребує перевірки значення.'}
function imageUrl(value){try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='images.pexels.com'?u.href:null}catch{return null}}
function sourceUrl(value){try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='www.pexels.com'?u.href:'https://www.pexels.com'}catch{return 'https://www.pexels.com'}}
for(const [key,entry] of Object.entries(catalog.entries)){
 const card=node('article',undefined,root);if(entry.reviewed)card.classList.add('done');node('h2',entry.word+' — '+entry.translation,card);node('p',entry.context||'',card);node('p','Пошук: '+entry.query,card);
 const status=node('p',entry.reviewed?'Перевірено':'Автоматичний вибір, не перевірено',card);status.className='status';const photos=node('div',undefined,card);photos.className='photos';
 for(const photo of entry.candidates||[]){const box=node('div',undefined,photos);box.className='photo';const label=node('label',undefined,box);const input=node('input',undefined,label);input.type='radio';input.name=key;input.checked=entry.selected?.id===photo.id;const url=imageUrl(photo.thumbnailUrl);if(url){const img=node('img',undefined,label);img.src=url;img.alt=photo.alt||entry.word;img.loading='lazy';img.referrerPolicy='no-referrer'}node('span',photo.alt||'Варіант',label);const credit=node('a','Photo by '+photo.photographer+' on Pexels',box);credit.href=sourceUrl(photo.url);credit.target='_blank';credit.rel='noopener noreferrer';input.onchange=()=>{entry.selected=photo;entry.reviewed=true;entry.status='matched';card.classList.add('done');status.textContent='Перевірено';summary()}}
 if(!entry.candidates?.length)node('p','Результатів немає. Можна уточнити запит і повторити лише ці слова.',card);
 const confirm=node('button','Підтвердити вибір',card);confirm.onclick=()=>{entry.reviewed=true;card.classList.add('done');status.textContent='Перевірено';summary()};const clear=node('button','Лишити без картинки',card);clear.onclick=()=>{entry.selected=null;entry.reviewed=true;entry.status='no_image';photos.querySelectorAll('input').forEach(x=>x.checked=false);card.classList.add('done');status.textContent='Без картинки';summary()};
}
summary();document.getElementById('save').onclick=()=>{catalog.updatedAt=new Date().toISOString();const url=URL.createObjectURL(new Blob([JSON.stringify(catalog,null,2)],{type:'application/json'}));const a=node('a');a.href=url;a.download='catalog.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
</script></html>`;
}
