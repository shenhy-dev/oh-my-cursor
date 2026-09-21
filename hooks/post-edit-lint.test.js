#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  quoteWinArg,
  winCmdLine,
  which,
  unsafeForCmd,
  cmdSpawnArgs,
  cmdExecutable,
  sameDir,
} = require('./post-edit-lint.js');

function afterCmdSStrip(wrapped) {
  assert.ok(wrapped.startsWith('"') && wrapped.endsWith('"'), wrapped);
  return wrapped.slice(1, -1);
}

function unquotedSegments(cmd) {
  return cmd.replace(/"(?:[^"]|"")*"/g, '');
}

assert.strictEqual(quoteWinArg('eslint'), 'eslint');
assert.strictEqual(quoteWinArg('--no-error-on-unmatched-pattern'), '--no-error-on-unmatched-pattern');
assert.strictEqual(quoteWinArg(''), '""');
assert.strictEqual(
  quoteWinArg('C:\\Program Files\\nodejs\\npx.cmd'),
  '"C:\\Program Files\\nodejs\\npx.cmd"',
);
assert.strictEqual(quoteWinArg('pwn.js & calc.exe & x.js'), '"pwn.js & calc.exe & x.js"');
assert.strictEqual(quoteWinArg('say "hi"'), '"say ""hi"""');
assert.strictEqual(quoteWinArg('a(b)'), '"a(b)"');
assert.strictEqual(quoteWinArg('x!y.js'), '"x!y.js"');
assert.strictEqual(quoteWinArg('x%PATH%y.js'), '"x%PATH%y.js"');

const inner = afterCmdSStrip(
  winCmdLine('C:\\Program Files\\nodejs\\npx.cmd', [
    'eslint',
    '--no-error-on-unmatched-pattern',
    'C:\\pwn.js & calc.exe & x.js',
  ]),
);

assert.ok(inner.startsWith('"C:\\Program Files\\nodejs\\npx.cmd" '), inner);
assert.ok(inner.includes(' eslint '), inner);
assert.ok(inner.endsWith('"C:\\pwn.js & calc.exe & x.js"'), inner);
assert.doesNotMatch(unquotedSegments(inner), /[&|<>()]/);

const pipeInner = afterCmdSStrip(
  winCmdLine('C:\\Program Files\\nodejs\\npx.cmd', ['eslint', 'x.js | calc.exe']),
);
assert.ok(pipeInner.includes('"x.js | calc.exe"'), pipeInner);
assert.doesNotMatch(unquotedSegments(pipeInner), /[&|<>()]/);

assert.ok(unsafeForCmd('x%CMDCMDLINE:~-1%&calc.exe&y.js'));
assert.ok(unsafeForCmd('x!CMDCMDLINE:~-1!y.js'));
assert.ok(!unsafeForCmd('C:\\ws\\app.js'));
assert.ok(!unsafeForCmd('C:\\Program Files\\nodejs\\npx.cmd'));

assert.strictEqual(
  cmdSpawnArgs('C:\\Program Files\\nodejs\\npx.cmd', [
    'eslint',
    'C:\\ws\\x%CMDCMDLINE:~-1%&calc.exe&y.js',
  ]),
  null,
);
assert.strictEqual(
  cmdSpawnArgs('C:\\Program Files\\nodejs\\npx.cmd', ['eslint', 'pwn.js & calc.exe & x.js']),
  null,
);

const argv = cmdSpawnArgs('C:\\Program Files\\nodejs\\npx.cmd', ['eslint', 'C:\\ws\\app.js']);
assert.ok(argv);
assert.deepStrictEqual(argv.slice(0, 4), ['/d', '/s', '/v:off', '/c']);
assert.ok(argv[4].includes('app.js'), argv[4]);

const fakeRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'omc-sys-'));
const trap = fs.mkdtempSync(path.join(os.tmpdir(), 'omc-trap-'));
const safe = fs.mkdtempSync(path.join(os.tmpdir(), 'omc-safe-'));
try {
  fs.mkdirSync(path.join(fakeRoot, 'System32'));
  fs.writeFileSync(path.join(fakeRoot, 'System32', 'cmd.exe'), '');
  fs.writeFileSync(path.join(trap, 'cmd.exe'), 'planted-cmd');
  assert.strictEqual(
    cmdExecutable({ SystemRoot: fakeRoot, ComSpec: path.join(trap, 'cmd.exe') }),
    path.join(fakeRoot, 'System32', 'cmd.exe'),
  );
  assert.strictEqual(cmdExecutable({ ComSpec: 'cmd.exe' }), null);

  fs.writeFileSync(path.join(trap, 'npx.cmd'), 'evil-cmd');
  fs.writeFileSync(path.join(trap, 'npx.exe'), 'evil-exe');
  fs.writeFileSync(path.join(safe, 'npx.cmd'), 'good-cmd');

  const fromCwdTrap = which('npx', {
    platform: 'win32',
    pathEnv: `${trap};${safe}`,
    cwd: trap,
  });
  assert.strictEqual(fromCwdTrap, path.join(safe, 'npx.cmd'));

  const dottedPath = which('npx', {
    platform: 'win32',
    pathEnv: `.;${safe}`,
    cwd: trap,
  });
  assert.strictEqual(dottedPath, path.join(safe, 'npx.cmd'));

  assert.ok(sameDir('C:\\Users\\Foo\\proj', 'c:\\users\\foo\\proj', 'win32'));
  assert.ok(sameDir('C:/proj/', 'c:\\proj', 'win32'));
  assert.ok(sameDir('\\\\?\\C:\\proj', 'C:\\proj', 'win32'));
  assert.ok(!sameDir('C:\\proj', 'C:\\other', 'win32'));
  assert.ok(!sameDir('/tmp/a', '/tmp/b', 'linux'));

  const mixedCaseCwd = which('npx', {
    platform: 'win32',
    pathEnv: `${trap.toUpperCase()};${safe}`,
    cwd: trap,
  });
  assert.strictEqual(mixedCaseCwd, path.join(safe, 'npx.cmd'));

  fs.writeFileSync(path.join(safe, 'npx.exe'), 'good-exe');
  const preferExe = which('npx', {
    platform: 'win32',
    pathEnv: safe,
    cwd: trap,
  });
  assert.strictEqual(preferExe, path.join(safe, 'npx.exe'));
} finally {
  fs.rmSync(fakeRoot, { recursive: true, force: true });
  fs.rmSync(trap, { recursive: true, force: true });
  fs.rmSync(safe, { recursive: true, force: true });
}

console.log('ok');
