#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { checkStaged } = require('./pre-commit-check.js');

const HERE = __dirname;

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function parsePayload(raw) {
  const text = String(raw || '').replace(/^\uFEFF/, '').trim();
  if (!text) return { ok: true, payload: {} };
  try {
    return { ok: true, payload: JSON.parse(text) };
  } catch {
    return { ok: false, payload: {} };
  }
}

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function allow() {
  emit({ continue: true, permission: 'allow' });
  process.exit(0);
}

function ask(msg) {
  emit({
    continue: true,
    permission: 'ask',
    userMessage: msg,
    agentMessage: msg,
  });
  process.exit(0);
}

function observe() {
  return process.env.OMC_HOOKS_OBSERVE === '1';
}

function decide(reason) {
  if (observe()) {
    emit({
      continue: true,
      permission: 'allow',
      agentMessage: `[observe] would block: ${reason}`,
    });
    process.exit(0);
  }
  emit({
    continue: false,
    permission: 'deny',
    userMessage: `Blocked by oh-my-cursor: ${reason}`,
    agentMessage: `Denied by policy: ${reason}. Adjust hooks/guard-shell.js or set OMC_HOOKS_OBSERVE=1 to override.`,
  });
  process.exit(0);
}

function hold(reason) {
  if (observe()) {
    emit({
      continue: true,
      permission: 'allow',
      agentMessage: `[observe] would hold for review: ${reason}`,
    });
    process.exit(0);
  }
  emit({
    continue: true,
    permission: 'ask',
    userMessage: `Held by oh-my-cursor for review: ${reason}`,
    agentMessage: `Held for review: ${reason}. Approve only if this credential/secret access is intended.`,
  });
  process.exit(0);
}

const raw = readStdin();
const parsed = parsePayload(raw);
let payload = parsed.payload;
let parseOk = parsed.ok;

const command = typeof payload.command === 'string' ? payload.command : '';
const cwd = typeof payload.cwd === 'string' ? payload.cwd : '';

if (process.env.OMC_HOOKS_DEBUG === '1') {
  try {
    const stamp = new Date().toISOString().replace(/\.\d+Z$/, '');
    fs.appendFileSync(path.join(HERE, 'last-invocation.log'), `${stamp}\t${command || '<unparsed>'}\n`);
  } catch {
    /* ignore */
  }
}

if (!parseOk) {
  if (observe()) allow();
  ask('oh-my-cursor guard could not parse the shell command; review before running');
}

if (!command) allow();

if (cwd) {
  try {
    if (fs.existsSync(cwd) && fs.statSync(cwd).isDirectory()) process.chdir(cwd);
  } catch {
    /* ignore */
  }
}

const destructive = [
  'rm -rf /',
  'rm -rf ~',
  'rm -rf /*',
  ':(){ :|:& };:',
];
if (destructive.some((p) => command.includes(p))) decide('destructive filesystem command');

if (
  (command.includes('git push') && command.includes('--force') && (command.includes('main') || command.includes('master'))) ||
  (command.includes('git push -f') && (command.includes('main') || command.includes('master')))
) {
  decide('force-push to a protected branch');
}

if (command.includes('git reset --hard origin/main') || command.includes('git reset --hard origin/master')) {
  decide('hard reset of a shared branch');
}

if (command.includes('chmod -R 777 /') || command.includes('mkfs') || (command.includes('dd if=') && command.includes('of=/dev/'))) {
  decide('system-level destructive command');
}

if (command.includes('git commit')) {
  const result = checkStaged(process.cwd());
  if (!result.ok) {
    const snippet = result.output.replace(/\s+/g, ' ').slice(0, 160);
    decide(`commit contains forbidden anti-patterns (${snippet})`);
  }
}

const secretNeedles = [
  '/.ssh/',
  '/.aws/',
  '/.gnupg/',
  'id_rsa',
  'id_dsa',
  'id_ecdsa',
  'id_ed25519',
  '.pem',
  '.netrc',
  '.pgpass',
  '/.kube/config',
  'kubeconfig',
  '/.docker/config.json',
  '/.config/gcloud/',
  '.aws/credentials',
  'appdata/roaming/gcloud',
];
const secretHaystack = command.replace(/\\/g, '/').toLowerCase();
if (secretNeedles.some((p) => secretHaystack.includes(p.toLowerCase()))) {
  hold('command accesses a credential/secret file');
}

allow();
