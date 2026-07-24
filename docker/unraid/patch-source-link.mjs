import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const root = '/usr/share/nginx/html';
const upstream = 'https://github.com/koala73/worldmonitor';
const source = process.env.WM_SOURCE_URL || 'https://github.com/imzenreally/worldmonitor-unraid-aio';
const extensions = new Set(['.html', '.js', '.json', '.map', '.txt']);
let replacements = 0;

async function walk(path) {
  for (const entry of await readdir(path)) {
    const child = join(path, entry);
    const metadata = await stat(child);
    if (metadata.isDirectory()) {
      await walk(child);
      continue;
    }
    const dot = entry.lastIndexOf('.');
    if (dot < 0 || !extensions.has(entry.slice(dot))) continue;
    const before = await readFile(child, 'utf8');
    const after = before.replaceAll(upstream, source);
    if (after !== before) {
      replacements += before.split(upstream).length - 1;
      await writeFile(child, after);
    }
  }
}

await walk(root);
if (replacements < 1) {
  throw new Error(`No visible source links matching ${upstream} were found`);
}
console.log(`Rewrote ${replacements} visible source link(s) to ${source}`);
