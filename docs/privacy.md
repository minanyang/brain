# Privacy

Transcripts contain everything: pasted internal documents, customer names, tool output with credentials, the occasional API key. The vault is where the distilled form of that ends up. Treat it accordingly.

## Rules

1. **Streams never enter a repository.** Transcripts are read in place and only their digests are written out.
2. **The secret gate runs on every write.** Before a digest or page is written, its text is scanned for key/token patterns (`AKIA…`, `sk-…`, `ghp_…`, `xoxb-…`, `-----BEGIN … PRIVATE KEY-----`, `Bearer …`, generic `password|secret|token\s*[:=]`). A hit aborts the write and logs the session id; the human decides.
3. **The distiller is told what not to carry.** No tool output, no code blocks over 5 lines, no credentials, no verbatim pasted documents — summarize the fact, not the artifact.
4. **The vault is private or local-only.** A private remote is acceptable for multi-device sync; a public one is not, ever.
5. **The pattern repository knows nothing.** Examples, templates, and tests in `brain` use fabricated data. Nothing in it is derived from a real vault.
6. **The brief is in scope.** If `brief.md` is injected at session start, it must pass the same gate as everything else because it is read on every session, in every repository — including public ones you may be asked to commit to.

## What the human still has to do

- Decide whether the vault gets a remote at all.
- Review `lint` output; the gate catches patterns, not judgment calls ("this customer's name should not be here").
- Keep per-machine config (`~/.brain/config.json`) out of git — it holds paths, not secrets, but it is per-device and will cause the same sync loops any other device-specific file does.
