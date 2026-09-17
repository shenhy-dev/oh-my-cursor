# Contributing to cursor-agents

Thanks for your interest in contributing. This project is a Cursor plugin (rules, agents, commands, hooks, skills) plus a project-scope installer for cloud agents; contributions that improve clarity, behavior, or docs are welcome.

## How to contribute

- **Bug reports & feature ideas:** Open an [issue](https://github.com/tmcfarlane/cursor-agents/issues).
- **Code/docs changes:** Open a pull request (PR) against `main`.

## Before you submit

1. **Agents & rules:** Keep agent manifests (in `agents/`) and the orchestrator rule (in `rules/`) consistent with the existing style and structure. One role per agent; the orchestrator stays the single always-on rule. YAML `name:` **must** be the filename stem (`toph`, not a sentence). Cursor's Task enum is that `name:` value; a flavorful sentence makes `Task(toph)` fail on the first call. Keep personality in `description`.
2. **Install script:** If you change file names or layout, update `install.sh` so install still works: `--user` copies the plugin to `~/.cursor/plugins/local/oh-my-cursor`; `--project` still writes `./.cursor/`. Keep `.cursor-plugin/plugin.json` in sync (explicit `agents` list must not include `protocols/team-avatar.md`).
3. **Docs:** Update README (or other docs) if you add agents, change behavior, or change how people install or use the project.

## Pull requests

- Branch from `main`, make focused commits, and target `main` with your PR.
- Describe what you changed and why; link any related issues.
- Ensure the installer still runs (e.g. `bash install.sh --dry-run` or a quick local install test) if you touched `install.sh`, `.cursor-plugin/`, or the repo layout.

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers this project.
