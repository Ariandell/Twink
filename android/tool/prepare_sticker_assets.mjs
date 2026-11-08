import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const folder = path.join(root, 'assets/word-images');
fs.mkdirSync(path.join(folder, 'images'), { recursive: true });
const source = path.join(root, 'assets/lexicon/index.json');
const lookup = path.join(folder, 'lookup.json');
const fields = ['word', 'translation', 'info1', 'info2', 'ex1', 'ex2'];
const entries = fs.existsSync(source) ? JSON.parse(fs.readFileSync(source, 'utf8')).entries ?? [] : [];
fs.writeFileSync(path.join(folder, 'lexicon.json'), JSON.stringify(entries.map(word =>
  Object.fromEntries(fields.map(key => [key, word[key] ?? ''])))));
if (fs.existsSync(source)) {
  const result = {};
  for (const word of JSON.parse(fs.readFileSync(source, 'utf8')).entries ?? []) {
    const images = [...new Set((word.images ?? []).map(p => p.id).filter(id => Number.isInteger(id) && id > 0 && fs.existsSync(path.join(folder, 'images', id + '.webp'))))];
    if (!images.length) continue;
    const key = word.word.trim().toLowerCase().replace(/\s+/g, ' ');
    result[key] = images;
  }
  for (const [word, images] of Object.entries(result)) {
    const head = word.split(',')[0];
    result[head] = [...new Set([...(result[head] ?? []), ...images])];
  }
  fs.writeFileSync(lookup, JSON.stringify(result));
} else if (!fs.existsSync(lookup)) {
  fs.writeFileSync(lookup, '{}');
}
console.log('Sticker assets prepared locally.');
