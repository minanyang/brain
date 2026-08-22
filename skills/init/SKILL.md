---
name: init
description: Create a Brain vault at a path and register it in ~/.brain/config.json. Use when the user asks to create, set up, or add a vault.
argument-hint: <path>
allowed-tools: Bash
---

Create a vault at `$ARGUMENTS` (ask for a path if none was given).

1. Ask one question, and only if the user has not already said: *which directories should feed this vault?* Offer `~/**` (everything under the home directory) as the default. Accept one or more globs; `**` means any depth. Check the globs already registered in `~/.brain/config.json` first: a new vault is inserted at the **front** of the list and routing takes the first match, so a `~/**` vault created after a narrow one silently swallows every session the narrow one was meant to catch. Say so before running. `exclude` is not a script flag — the user adds it to the vault's entry in the config afterwards.
2. The vault's name is the directory's basename unless the user gives one.
3. Run:

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/init-vault.sh" <path> --name <name> --include <glob> [<glob> ...]
   ```

4. Show its output verbatim.

Do not create a remote — the vault will hold distilled private conversations, and publishing it is a separate decision the owner makes later — and do not run the backfill unless asked: it is one model call per session over the entire history. If the script reports that the name is already registered, ask for a different name.
