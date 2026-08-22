---
name: init
description: Use when the user asks to create, set up, add, or register a Brain vault, or mentions /brain:init or starting a brain. Creates the vault and registers it with its routing globs.
argument-hint: <path>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/init-vault.sh *), Read
---

Create a vault at `$ARGUMENTS` (ask for a path if none was given).

1. Ask one question, and only if the user has not already said: *which directories should feed this vault?* `~/**` — everything under the home directory — is the right default for a first vault. `**` means any depth.
2. Branch on what is already registered in `~/.brain/config.json`:
   - **No vault yet** → take the answer and continue.
   - **A vault already exists** → read its globs and say, before running, which of its sessions the new vault will take. A new vault is inserted at the **front** of the list and routing takes the first match, so a `~/**` vault created after a narrow one silently swallows everything the narrow one was meant to catch. Create the catch-all first and narrow vaults after it, or expect to reorder the file by hand.
3. Run (the name defaults to the directory's basename):

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/init-vault.sh" <path> --name <name> --include <glob> [<glob> ...]
   ```

4. Show its output verbatim. If it reports the name is already registered, ask for a different one. An existing directory is safe — the script reuses a repository rather than re-initializing it, and a vault created inside a directory an `include` already covers is safe too, because sessions whose cwd is inside any vault are never distilled.
5. Point at the backfill, with its limit: `/brain:distill --all --days 30` (`--days` is read only when `--all` is set; on its own it distills nothing). Claude Code deletes transcripts after about 30 days, so on a fresh install that is very nearly the whole history — `--all` is worth the extra calls only on a machine whose retention was raised.

Never create a remote: the vault holds distilled private conversations, and publishing it is a decision the owner makes later, once they have read what it actually contains.

Never run the backfill unless asked — it is one model call per session over the whole history.

Never pass an exclusion to the script; there is no such flag. Exclusions are added by hand to the vault's entry in `~/.brain/config.json`:

```json
{ "name": "personal", "path": "~/vaults/personal", "include": ["~/**"], "exclude": ["~/Repos/acme/**", "/tmp/**"] }
```
