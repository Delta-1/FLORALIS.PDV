import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, 'dist-native');
const files = [
  'index.html',
  'pdv.html',
  'styles.css',
  'config.js',
  'backend.js',
  'app.js',
  'document-studio.js',
  'import-wizard.js',
  'pdv-experience.js',
  'native-shell.js',
  'pwa.js',
  'sw.js',
  'manifest.webmanifest'
];

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await Promise.all(files.map(file => cp(join(root, file), join(output, file))));
await cp(join(root, 'assets'), join(output, 'assets'), { recursive: true });
console.log(`Aplicativo preparado em ${output}`);
