#!/usr/bin/env bash
# Install Codex bindings for this checkout, sharing ~/.brain/config.json and vaults.
# install-codex.sh [--codex-home <path>] [--skills-dir <path>]
# Does not copy the vault, start a backfill, or overwrite unrelated skills/hooks.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
codex_home="${CODEX_HOME:-$HOME/.codex}" skills_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --codex-home) codex_home=$(expand_home "$2"); shift ;;
    --skills-dir) skills_dir=$(expand_home "$2"); shift ;;
    --help|-h) echo 'usage: install-codex.sh [--codex-home <path>] [--skills-dir <path>]'; exit 0 ;;
    *) log "unknown option: $1"; exit 2 ;;
  esac
  shift
done
skills_dir="${skills_dir:-$codex_home/skills}"
config_exists || { log "create or register a vault with init-vault.sh first"; exit 1; }
command -v codex >/dev/null || { log "install the Codex CLI first"; exit 1; }
case "$codex_home:$skills_dir" in /*:/*) ;; *) log "installation paths must be absolute"; exit 2 ;; esac

# Preflight all owned destinations before making changes.
for op in init distill ingest query lint clip; do
  target="$skills_dir/brain-$op"
  [ ! -e "$target" ] || [ -f "$target/.brain-managed" ] || {
    log "unmanaged skill already exists: $target"; exit 1;
  }
done
runtime="$codex_home/brain-hook.sh"
[ ! -e "$runtime" ] || grep -q '^# Managed by Brain' "$runtime" || {
  log "unmanaged file already exists: $runtime"; exit 1;
}
hooks="$codex_home/hooks.json"
[ ! -e "$hooks" ] || jq -e 'type == "object" and ((.hooks // {}) | type == "object")' "$hooks" >/dev/null

mkdir -p "$skills_dir" "$codex_home"
for op in init distill ingest query lint clip; do
  target="$skills_dir/brain-$op"
  mkdir -p "$target"
  # The operational rules remain shared. Only host bindings and discovery metadata differ.
  jq -Rrs --arg root "$BRAIN_ROOT" --arg op "$op" '
    gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $root)
    | gsub("/brain:"; "$brain-")
    | split("\n")
    | map(select(startswith("allowed-tools:") or startswith("disable-model-invocation:") or startswith("argument-hint:") | not))
    | map(if startswith("name: ") then "name: brain-" + $op else . end) | join("\n")
  ' "$BRAIN_ROOT/skills/$op/SKILL.md" > "$target/SKILL.md"
  if [ "$op" = distill ]; then
    # A Codex backfill uses Codex by default; a user can still explicitly override either flag.
    sed -i '' 's|/scripts/distill.sh" |/scripts/distill.sh" --host codex --provider codex |g' "$target/SKILL.md" 2>/dev/null \
      || sed -i 's|/scripts/distill.sh" |/scripts/distill.sh" --host codex --provider codex |g' "$target/SKILL.md"
  fi
  if [ -d "$BRAIN_ROOT/skills/$op/references" ]; then
    mkdir -p "$target/references"
    for ref in "$BRAIN_ROOT/skills/$op/references/"*; do
      jq -Rrs --arg root "$BRAIN_ROOT" 'gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $root) | gsub("/brain:"; "$brain-")' \
        "$ref" > "$target/references/$(basename "$ref")"
    done
  fi
  printf '%s\n' "$BRAIN_ROOT" > "$target/.brain-managed"
done

# Quote shell values with bash printf, not JSON quoting. PATH includes the Node
# runtime so hooks launched by the desktop app can execute the npm Codex shim.
{
  printf '#!/usr/bin/env bash\n# Managed by Brain; rerun install-codex.sh to refresh.\n'
  printf 'export BRAIN_ROOT=%q\n' "$BRAIN_ROOT"
  printf 'export BRAIN_CONFIG=%q\n' "$BRAIN_CONFIG"
  printf 'export CODEX_HOME=%q\n' "$codex_home"
  printf 'export PATH=%q\n' "$PATH"
  printf 'exec "$BRAIN_ROOT/hooks/codex-session.sh" "$@"\n'
} > "$runtime"
chmod +x "$runtime"

if [ -f "$hooks" ]; then
  [ -f "$hooks.brain-backup" ] || cp -p "$hooks" "$hooks.brain-backup"
else
  printf '{"hooks":{}}\n' > "$hooks"
fi
# Preserve other hook groups, and replace only Brain's exact managed commands.
printf -v command '%q' "$runtime"
jq --arg cmd "$command" '
  def install($event; $suffix; $timeout):
    .hooks[$event] = ([.hooks[$event][]? | .hooks |= map(select(.command != ($cmd + $suffix))) | select(.hooks | length > 0)]
      + [{hooks: [{type: "command", command: ($cmd + $suffix), timeout: $timeout}]}]);
  install("SessionStart"; " start"; 10) | install("SessionEnd"; " end"; 3)
' "$hooks" > "$hooks.tmp"
mv "$hooks.tmp" "$hooks"

[ -f "$BRAIN_CONFIG.codex-backup" ] || cp -p "$BRAIN_CONFIG" "$BRAIN_CONFIG.codex-backup"
jq --arg h "$codex_home" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  .codex_transcripts = ((.codex_transcripts // []) + [$h + "/sessions", $h + "/archived_sessions"] | unique)
  | .codex_enabled_at //= $now
' "$BRAIN_CONFIG" > "$BRAIN_CONFIG.tmp"
mv "$BRAIN_CONFIG.tmp" "$BRAIN_CONFIG"

while IFS= read -r vp; do
  vp=$(expand_home "$vp")
  [ -d "$vp" ] || continue
  mkdir -p "$vp/sources/sessions/claude" "$vp/sources/sessions/codex"
  # One shared local override file: Codex reads the existing CLAUDE.md explicitly.
  if ! grep -q '<!-- brain-codex -->' "$vp/AGENTS.md" 2>/dev/null; then
    cat >> "$vp/AGENTS.md" <<EOF

<!-- brain-codex -->
## Brain shared vault

Read \`$BRAIN_ROOT/docs/schema.md\` and this vault's \`CLAUDE.md\` before working here. The latter is the shared glossary and local overrides for all hosts. Read \`brief.md\` and \`index.md\`, then the relevant pages; cite their sources. Use the installed \$brain-query, \$brain-ingest, \$brain-clip and \$brain-lint skills. Before editing, acquire the writer lease as those skills describe. Finish through Brain scripts and release the lease. Never create a separate per-agent wiki.
<!-- /brain-codex -->
EOF
  fi
done < <(jq -r '.vaults[].path' "$BRAIN_CONFIG")
printf 'Installed six Brain skills in %s\nHooks: %s\nShared routing: %s\n' "$skills_dir" "$hooks" "$BRAIN_CONFIG"
printf 'Restart Codex; review and trust the two Brain hooks with /hooks. No backfill was started.\n'
