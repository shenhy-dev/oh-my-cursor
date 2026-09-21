#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HERE = __dirname;

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function which(bin) {
  const cmd = process.platform === 'win32' ? 'where' : 'which';
  const names = process.platform === 'win32' ? [`${bin}.cmd`, `${bin}.exe`, bin] : [bin];
  for (const name of names) {
    const r = spawnSync(cmd, [name], { encoding: 'utf8' });
    if (r.status === 0 && r.stdout && r.stdout.trim()) {
      return r.stdout.split(/\r?\n/).map((s) => s.trim()).find(Boolean) || name;
    }
  }
  return null;
}

function run(bin, args) {
  const resolved = which(bin);
  if (!resolved) return;
  const opts = { stdio: 'inherit', encoding: 'utf8' };
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(resolved)) {
    opts.shell = true;
    opts.windowsHide = true;
  }
  spawnSync(resolved, args, opts);
}

let payload = {};
const raw = readStdin();
const text = String(raw || '').replace(/^\uFEFF/, '').trim();
if (text) {
  try {
    payload = JSON.parse(text);
  } catch {
    process.exit(0);
  }
}

const file = typeof payload.file_path === 'string' ? payload.file_path : '';

if (process.env.OMC_HOOKS_DEBUG === '1') {
  try {
    const stamp = new Date().toISOString().replace(/\.\d+Z$/, '');
    fs.appendFileSync(path.join(HERE, 'last-invocation.log'), `${stamp}\tedit\t${file || '<unparsed>'}\n`);
  } catch {
    /* ignore */
  }
}

if (!file || !fs.existsSync(file) || !fs.statSync(file).isFile()) process.exit(0);

const ext = path.extname(file).slice(1);

try {
  if (ext === 'ts' || ext === 'tsx' || ext === 'js' || ext === 'jsx') {
    run('npx', ['eslint', '--no-error-on-unmatched-pattern', file]);
  } else if (ext === 'py') {
    if (which('ruff')) run('ruff', ['check', file]);
    else run('flake8', [file]);
  } else if (ext === 'rs') {
    run('cargo', ['clippy', '--message-format=short']);
  } else if (ext === 'go') {
    run('golangci-lint', ['run', file]);
  }
} catch {
  /* informational only */
}

process.exit(0);
