---
name: init
description: Create a Brain vault at a path and register it in ~/.brain/config.json. Use when the user asks to create, set up, or add a vault.
argument-hint: <path>
allowed-tools: Bash
---

Create a vault at `$ARGUMENTS` (ask for a path if none was given).

1. Ask one question, and only if the user has not already said: *which directories should feed this vault?* Offer `~/**` (everything under the home directory) as the default. Accept one or more globs; `**` means any depth.
2. The vault's name is the directory's basename unless the user gives one.
3. Run:

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/init-vault.sh" <path> --name <name> --include <glob> [<glob> ...]
   ```

4. Show its output verbatim. It lists the path, the registered include globs, and the next step (`/brain:distill --all` to backfill, or `--days 30` for a smaller first run).

Do not create a remote, and do not run the backfill unless asked. If the script reports that the name is already registered, ask for a different name.
