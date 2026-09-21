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

function isRunnable(file, platform) {
  try {
    const st = fs.statSync(file);
    if (!st.isFile()) return false;
    if (platform === 'win32') return true;
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Resolve a binary from PATH only (absolute dirs, never cwd / `.`).
 * Windows prefers `.exe` then `.cmd`/`.bat` so native tools skip cmd.exe.
 */
function which(bin, opts) {
  const o = opts || {};
  const platform = o.platform || process.platform;
  const envPath = o.pathEnv != null ? o.pathEnv : process.env.PATH || '';
  const cwd = path.resolve(o.cwd || process.cwd());
  const sep = platform === 'win32' ? ';' : ':';
  const names = platform === 'win32' ? [`${bin}.exe`, `${bin}.cmd`, `${bin}.bat`, bin] : [bin];

  const dirs = envPath.split(sep).map((d) => {
    let s = String(d).trim();
    if (
      (s.startsWith('"') && s.endsWith('"') && s.length >= 2) ||
      (s.startsWith("'") && s.endsWith("'") && s.length >= 2)
    ) {
      s = s.slice(1, -1);
    }
    return s;
  }).filter(Boolean);

  for (const name of names) {
    for (const dir of dirs) {
      if (dir === '.' || dir === './' || dir === '.\\') continue;
      if (!path.isAbsolute(dir)) continue;
      let absDir;
      try {
        absDir = path.resolve(dir);
      } catch {
        continue;
      }
      if (absDir === cwd) continue;
      const candidate = path.join(absDir, name);
      if (isRunnable(candidate, platform)) return candidate;
    }
  }
  return null;
}

/** Quote one argv token for cmd.exe so spaces and metacharacters stay literal. */
function quoteWinArg(arg) {
  const s = String(arg);
  if (s.length === 0) return '""';
  if (!/[\s"&|<>()^%!]/.test(s)) return s;
  return `"${s.replace(/"/g, '""')}"`;
}

/**
 * Command-line remainder for `cmd.exe /d /s /c`.
 * `/s` strips the first and last `"` on that remainder, so wrap the already-quoted argv.
 */
function winCmdLine(bin, args) {
  const line = [quoteWinArg(bin), ...args.map(quoteWinArg)].join(' ');
  return `"${line}"`;
}

/** `%`/`!` expand inside quotes; `&|<>^` are cmd operators if quotes break. */
function unsafeForCmd(s) {
  return /[%!&|<>^\r\n\0]/.test(String(s));
}

function cmdSpawnArgs(resolved, args) {
  if ([resolved, ...args].some(unsafeForCmd)) return null;
  return ['/d', '/s', '/v:off', '/c', winCmdLine(resolved, args)];
}

function cmdExecutable(env) {
  const e = env || process.env;
  const root = e.SystemRoot || e.WINDIR;
  if (root) {
    const candidate = path.join(root, 'System32', 'cmd.exe');
    try {
      if (fs.statSync(candidate).isFile()) return candidate;
    } catch {
      /* fall through */
    }
  }
  if (e.ComSpec && path.isAbsolute(e.ComSpec)) return e.ComSpec;
  return null;
}

function run(bin, args, opts) {
  const resolved = which(bin, opts);
  if (!resolved) return;
  const spawnOpts = { stdio: 'inherit', encoding: 'utf8', windowsHide: true };
  const platform = (opts && opts.platform) || process.platform;
  if (platform === 'win32' && /\.(cmd|bat)$/i.test(resolved)) {
    const argv = cmdSpawnArgs(resolved, args);
    if (!argv) return;
    const cmd = cmdExecutable((opts && opts.env) || process.env);
    if (!cmd) return;
    spawnSync(cmd, argv, { ...spawnOpts, windowsVerbatimArguments: true });
    return;
  }
  spawnSync(resolved, args, spawnOpts);
}

function main() {
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

  if (!file || /[\r\n\0]/.test(file) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    process.exit(0);
  }

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
}

module.exports = {
  quoteWinArg,
  winCmdLine,
  which,
  run,
  unsafeForCmd,
  cmdSpawnArgs,
  cmdExecutable,
};

if (require.main === module) {
  main();
}
