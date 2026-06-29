#!/usr/bin/env node
import { access, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const requiredFiles = [
  'site/assets/docsify-vue.css',
  'site/assets/example-runner.js',
  'site/assets/fonts.css',
  'site/assets/fonts/dm-sans-400.woff2',
  'site/assets/fonts/dm-sans-500.woff2',
  'site/assets/fonts/dm-sans-600.woff2',
  'site/assets/fonts/dm-sans-700.woff2',
  'site/assets/fonts/source-code-pro-400.woff2',
  'site/assets/fonts/source-code-pro-500.woff2',
  'site/assets/prism.css',
  'site/assets/prism-core.min.js',
  'site/assets/prism-bash.min.js',
  'site/assets/prism-erlang.min.js',
  'site/assets/prism-http.min.js',
  'site/assets/prism-json.min.js',
  'site/assets/prism-lua.min.js',
  'site/assets/prism-markdown.min.js',
  'site/assets/site.css',
  'docs/assets/images/aosvg1.svg',
  'docs/assets/images/aosvg2.svg',
  'docs/assets/images/aosvg3.svg'
];

const missing = [];

for (const rel of requiredFiles) {
  try {
    await access(path.join(root, rel));
  } catch {
    missing.push(rel);
  }
}

await rm(path.join(root, 'dist'), { recursive: true, force: true });

if (missing.length) {
  console.error('Missing source-served docs assets:');
  for (const rel of missing) console.error(`- ${rel}`);
  process.exit(1);
}

console.log(`Docs source asset check passed for ${requiredFiles.length} files`);
console.log('No dist/ tree is emitted; HyperBEAM serves site/assets and docs/assets directly.');
