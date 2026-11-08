import { readFile, writeFile, mkdir } from 'node:fs/promises';
const root = new URL('../../android/assets/icons/', import.meta.url);
await mkdir(root, {recursive:true});
const html = await readFile(new URL('../public/classic/index.html',import.meta.url),'utf8');
const buttons={user:'nav-profile-btn',book:'nav-dictionary-btn',play:'nav-study-btn',upload:'nav-import-btn',settings:'nav-settings-btn',back:'btn-exit-session',volume:'btn-quick-toggle-audio',filter:'dict-mobile-filter-toggle',close:'btn-close-settings',help:'btn-exam-help'};
for(const [name,id] of Object.entries(buttons)){
 const start=html.indexOf(`id="${id}"`),svg=html.slice(start).match(/<svg[\s\S]*?<\/svg>/)?.[0];
 if(svg) await writeFile(new URL(name+'.svg',root),svg.replace(/stroke="currentColor"/g,'stroke="#ffffff"'));
}
// Keep dictionary action contours identical to the original word/idiom lists.
const dictionary = await readFile(new URL('../public/classic/app.js', import.meta.url), 'utf8');
for (const [name, className] of Object.entries({edit: 'btn-edit', trash: 'btn-delete'})) {
 const button = dictionary.match(new RegExp(`<button class="btn-icon ${className}"[\\s\\S]*?<\\/button>`))?.[0];
 const svg = button?.match(/<svg[\s\S]*?<\/svg>/)?.[0];
 if (!svg) throw new Error(`Original dictionary icon not found: ${className}`);
 await writeFile(new URL(name + '.svg', root), svg.replace(/stroke="currentColor"/g, 'stroke="#ffffff"'));
}
const paths={
 chat:'<path d="M21 15a2 2 0 0 1-2 2H7l-5 5V5a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2Z"/>',
 'check-circle':'<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14M22 4 12 14.01l-3-3"/>',
 plus:'<path d="M12 5v14M5 12h14"/>',
 check:'<polyline points="20 6 9 17 4 12"/>',
 search:'<circle cx="11" cy="11" r="8"/><path d="m21 21-4.4-4.4"/>',
 download:'<path d="M12 3v12m-5-5 5 5 5-5M5 15v6h14v-6"/>',
 grid:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
 list:'<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
 star:'<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
 right:'<polyline points="9 18 15 12 9 6"/>',
 left:'<polyline points="15 18 9 12 15 6"/>',
 down:'<polyline points="6 9 12 15 18 9"/>',
 sort:'<path d="M4 6h16M7 12h13M10 18h10"/>',
 folder:'<path d="M3 7V5h6l2 2h10v13H3Z"/>',
 calendar:'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 3v18M16 3v18M3 9h18M3 16h18"/>',
 link:'<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
 globe:'<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10Z"/>',
 trophy:'<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6M18 9h1.5a2.5 2.5 0 0 0 0-5H18M4 22h16M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22M18 2H6v7a6 6 0 0 0 12 0V2Z"/>',
 zap:'<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
 muted:'<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="m17 9 6 6m0-6-6 6"/>',
 mic:'<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8"/>',
 eye:'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
 logout:'<path d="M9 3H4v18h5M9 12h12m-5-5 5 5-5 5"/>',
 clock:'<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
 image:'<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8" cy="8" r="1"/><path d="m21 15-5-5L5 21"/>',
};
for(const [name,body] of Object.entries(paths)) await writeFile(new URL(name+'.svg',root),`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`);
console.log('Native SVG icons prepared');
