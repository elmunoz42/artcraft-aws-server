#!/usr/bin/env node
// Install the Craft CLIs named on the command line from apps.lock.json.
// Each archive is downloaded, checked against its pinned SHA-256, and only then extracted.
// The headless <app>-cli is linked into /usr/local/bin; the desktop GUI binary is removed.
'use strict';
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const lock = JSON.parse(fs.readFileSync(path.join(__dirname, 'apps.lock.json'), 'utf8')).apps;
const wanted = process.argv.slice(2).join(' ').split(/[\s,]+/).filter(Boolean);
if (!wanted.length) { console.error('no apps requested'); process.exit(1); }

function findCli(dir, name) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'share') continue; // completions and man pages share the CLI's name
      const hit = findCli(p, name);
      if (hit) return hit;
    } else if (entry.name === name && (fs.statSync(p).mode & 0o111)) {
      return p;
    }
  }
  return null;
}

for (const app of wanted) {
  const pin = lock[app];
  if (!pin) { console.error(`unknown app "${app}". Known: ${Object.keys(lock).join(', ')}`); process.exit(1); }
  const archive = `/tmp/${app}.tar.gz`;
  const dest = `/opt/craft/${app}`;
  console.log(`${app} ${pin.version}: downloading ${pin.url}`);
  execFileSync('curl', ['-fsSL', '--retry', '3', '-o', archive, pin.url], { stdio: 'inherit' });
  const sum = crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  if (sum !== pin.sha256) { console.error(`${app}: checksum mismatch (got ${sum}, pinned ${pin.sha256})`); process.exit(1); }
  fs.mkdirSync(dest, { recursive: true });
  execFileSync('tar', ['-xzf', archive, '-C', dest, '--strip-components=1', '--no-same-owner'], { stdio: 'inherit' });
  fs.unlinkSync(archive);
  const cli = findCli(dest, pin.cli);
  if (!cli) { console.error(`${app}: ${pin.cli} not found in the archive`); process.exit(1); }
  const gui = path.join(path.dirname(cli), app);
  if (fs.existsSync(gui)) fs.unlinkSync(gui);
  fs.symlinkSync(cli, `/usr/local/bin/${pin.cli}`);
  const version = execFileSync(cli, ['--version'], { encoding: 'utf8' }).trim();
  console.log(`${app}: ok (${version})`);
}
