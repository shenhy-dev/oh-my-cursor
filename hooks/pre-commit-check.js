#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function gitStagedFiles(cwd) {
  const r = spawnSync('git', ['diff', '--cached', '--name-only', '--diff-filter=ACM'], {
    cwd: cwd || process.cwd(),
    encoding: 'utf8',
  });
  if (r.status !== 0 || !r.stdout) return [];
  return r.stdout.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}

function linesMatching(content, re) {
  return content.split(/\r?\n/).reduce((acc, line, i) => {
    if (re.test(line)) acc.push(`${i + 1}:${line}`);
    return acc;
  }, []);
}

function checkFile(filePath) {
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch {
    return [];
  }
  const ext = path.extname(filePath).slice(1);
  const hits = [];
  const add = (re, label) => {
    const ms = linesMatching(content, re);
    if (ms.length) hits.push({ label, samples: ms.slice(0, 5) });
  };

  if (ext === 'ts' || ext === 'tsx' || ext === 'js' || ext === 'jsx') {
    add(/as any/, "Type safety: 'as any' suppresses type checking");
    add(/@ts-ignore/, "Type safety: '@ts-ignore' suppresses errors");
    add(/@ts-expect-error/, "Type safety: '@ts-expect-error' suppresses errors");
    add(/catch(?:\s*\([^)]*\))?\s*\{\s*\}/, 'Error handling: empty catch block');
  } else if (ext === 'py') {
    add(/except:\s*$/, 'Error handling: bare except clause');
    add(/pass\s*$/, 'Error handling: potential empty except/pass');
  }
  return hits;
}

function checkStaged(cwd) {
  const root = cwd || process.cwd();
  const files = gitStagedFiles(root);
  if (!files.length) return { ok: true, output: '' };

  let violations = 0;
  const lines = [];
  for (const rel of files) {
    const abs = path.isAbsolute(rel) ? rel : path.join(root, rel);
    if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) continue;
    const hits = checkFile(abs);
    for (const hit of hits) {
      violations += 1;
      lines.push(`VIOLATION in ${rel}: ${hit.label}`);
      for (const s of hit.samples) lines.push(s);
      lines.push('');
    }
  }
  if (violations > 0) {
    lines.push(`Found ${violations} constraint violation(s). Fix before committing.`);
    return { ok: false, output: lines.join('\n') };
  }
  return { ok: true, output: '' };
}

module.exports = { checkStaged, checkFile };

if (require.main === module) {
  const result = checkStaged(process.cwd());
  if (result.output) process.stdout.write(result.output + (result.output.endsWith('\n') ? '' : '\n'));
  process.exit(result.ok ? 0 : 1);
}
