---
name: exploring-codebases
description: Semantic search for codebases. Locates matches then expands them into full functions/classes so results are complete, syntactically valid code blocks rather than fragmented lines. Use when looking for specific implementations, examples, or references where full context is needed.
metadata:
  version: 0.3.1
---

# Exploring Codebases

Find matches, then return the *entire* function or class containing the match — not a handful of surrounding lines. Prefer Cursor tools. Do not shell out to tree-sitter, `uv`, or plugin-local search scripts; those paths are not shipped with this plugin.

## Progressive Disclosure

**By default, return signatures only** (docstrings + declarations without function bodies), reducing token usage. Expand to full implementations only when the caller needs bodies.

## Workflow

1. **Locate** with `Grep` (literal/regex), `Glob` (path constraints), or `SemanticSearch` (intent). Batch related queries.
2. **Expand** each hit by `Read`ing the enclosing function, class, method, interface, enum, struct, trait, or module — not a 5-line window.
3. **Deduplicate** semantically (same symbol from multiple hits → one block).
4. **Report** complete, syntactically valid blocks with **absolute** file paths.

## Examples

**Find class signatures:** Grep/SemanticSearch for `class User`, then Read the class header and docstring. Report the signature, not the whole file.

**Find a full method implementation:** Grep for `def validate` / `function validate`, then Read the entire method body.

**Constrain by language:** pass a glob such as `*.py` to Grep, or search under a directory path.

## Scope and Limitations

**Returns structural code elements** — functions, classes, methods, interfaces, enums, structs, traits, and modules across common languages (Python, JavaScript, TypeScript, Go, Rust, Ruby, Java, C, C++, PHP, C#).

**Does not return:**
- Import/require statements
- Module-level variable assignments or constants
- Standalone decorators (decorators attached to functions/classes are included with their parent)
- Type aliases or standalone type annotations
- Comments outside of functions/classes

For these non-structural elements, use `Grep` directly.
