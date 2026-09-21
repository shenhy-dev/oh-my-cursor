#!/usr/bin/env node
'use strict';

const assert = require('assert');
const { quoteWinArg, winCmdLine } = require('./post-edit-lint.js');

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

console.log('ok');
