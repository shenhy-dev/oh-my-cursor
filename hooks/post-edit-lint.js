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
  const r = spawnSync(cmd, [bin], { encoding: 'utf8' });
  return r.status === 0;
}

function run(bin, args) {
  spawnSync(bin, args, { stdio: 'inherit', encoding: 'utf8' });
}

let payload = {};
const raw = readStdin();
if (raw.trim()) {
  try {
    payload = JSON.parse(raw);
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
    if (which('npx')) run('npx', ['eslint', '--no-error-on-unmatched-pattern', file]);
  } else if (ext === 'py') {
    if (which('ruff')) run('ruff', ['check', file]);
    else if (which('flake8')) run('flake8', [file]);
  } else if (ext === 'rs') {
    if (which('cargo')) run('cargo', ['clippy', '--message-format=short']);
  } else if (ext === 'go') {
    if (which('golangci-lint')) run('golangci-lint', ['run', file]);
  }
} catch {
  /* informational only */
}

process.exit(0);
