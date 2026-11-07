import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const folder = path.join(root, 'assets/word-images');
fs.mkdirSync(path.join(folder, 'images'), { recursive: true });
const source = path.join(root, 'assets/lexicon/index.json');
const lookup = path.join(folder, 'lookup.json');
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
