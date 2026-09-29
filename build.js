const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const output = path.join(root, 'build-output');

fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(path.join(output, 'public'), { recursive: true });
fs.cpSync(path.join(root, 'public'), path.join(output, 'public'), { recursive: true });

for (const file of ['app.js', 'package.json', 'package-lock.json', 'nginx.windows.conf']) {
  const source = path.join(root, file);
  if (fs.existsSync(source)) fs.copyFileSync(source, path.join(output, file));
}

for (const file of ['public/index.html', 'app.js', 'package.json', 'nginx.windows.conf']) {
  if (!fs.existsSync(path.join(output, file))) {
    throw new Error(`Build output is missing ${file}`);
  }
}

console.log(`Build output created at ${output}`);