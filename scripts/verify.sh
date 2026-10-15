#!/usr/bin/env bash
# verify.sh <vault-path> [--all] — re-check every git marker on the wiki pages.
#
# A status claim that git can settle carries a marker (docs/schema.md, "Status claims"):
#   (verified 2026-09-22: ~/Repos/acme-billing a1b2c3d in origin/main)
#   (verified 2026-09-22: ~/Repos/acme-billing a1b2c3d not-in origin/main)
# A page's status claim goes stale silently when a branch moves; this finds the ones that
# have. Output, one line per marker that needs attention (every marker with --all):
#   <STATE>\t<page>:<line>\t<marker>\t<detail>
# STATE is HOLDS, STALE, NO-REPO, NO-COMMIT or NO-REF. Local refs only — it never
# fetches, so a remote-tracking ref is as fresh as the last fetch.
#
# A commit that reached a branch through a squash or a rebase is not an ancestor of it,
# so before calling an `in` claim stale (or a `not-in` claim still true) it looks for an
# equivalent commit on the branch: the same patch (`git cherry`), or the same subject.
# Fields are matched against fixed patterns and passed to git as arguments, never evaluated.
set -euo pipefail
vp="${1:?vault path}"; all=false
[ "${2:-}" = --all ] && all=true
cd "$vp"

wiki_dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sed 's|^\./||' | sort)
[ -n "$wiki_dirs" ] || exit 0

g() { git -C "$repo" --no-pager "$@"; }
cache=$(mktemp "${TMPDIR:-/tmp}/brain-verify.XXXXXX"); trap 'rm -f "$cache"' EXIT

# equivalent <commit> <ref> -> prints a commit on <ref> carrying the same change, if any
equivalent() {
  local c="$1" r="$2" subj since hit
  hit=$(g cherry "$r" "$c" "$c^" 2>/dev/null | awk '$1 == "-" { print $2; exit }' || true)
  [ -n "$hit" ] && { printf 'an equal patch'; return; }
  subj=$(g log -1 --format=%s "$c" 2>/dev/null) || return 0
  since=$(g log -1 --format=%cs "$c" 2>/dev/null) || return 0
  g log --format='%h%x09%s' --since="$since" "$r" 2>/dev/null \
    | awk -F'\t' -v s="$subj" 'index($2, s) == 1 { print $1; exit }' || true
}

# arrival <commit> <ref> -> prints "<short> <date>" for the merge that carried <commit> onto
# <ref>, or nothing. Reporting the ref's tip instead, which this did until 2026-10-15, dates a
# claim to the day someone happened to run the check rather than the day the thing shipped: a
# commit that reached `develop` on the 1st and `main` in the 10th's release was reported as
# arriving on whatever `main` pointed at, and twelve pages were rewritten with the wrong date.
#
# An ancestry-path walk alone is not enough either, for two reasons. It returns the merge into
# whichever branch took the commit first: for a commit that went to `develop` nine days before the
# release, it names that merge rather than the release into `main`. And `--reverse` orders by
# ancestry, not by date, so its first line is not the earliest. Intersecting the candidates with
# the ref's own first-parent spine keeps only merges that are on that ref, and because rev-list
# prints newest first, the last surviving line is the oldest - the arrival.
arrival() {
  local c="$1" r="$2" cands f hit
  cands=$(g log --merges --ancestry-path --format='%H' "$c..$r" 2>/dev/null) || return 1
  [ -n "$cands" ] || return 1
  f=$(mktemp "${TMPDIR:-/tmp}/brain-arrival.XXXXXX") || return 1
  printf '%s\n' "$cands" > "$f"
  hit=$(g rev-list --first-parent "$r" 2>/dev/null | grep -Fx -f "$f" | tail -1)
  rm -f "$f"
  [ -n "$hit" ] || return 1
  g log -1 --format='%h %cs' "$hit"
}

while IFS= read -r hit; do
  loc=${hit%%:\(verified*}                       # page:line
  marker=${hit#"$loc":}
  body=${marker#\(verified }; body=${body%\)}    # 2026-09-22: <repo> <commit> <rel> <ref>
  rest=${body#*: }
  # The last three fields are fixed tokens; the repository path is everything before them,
  # so a path may contain spaces.
  ref=${rest##* }; rest=${rest% *}
  rel=${rest##* }; rest=${rest% *}
  commit=${rest##* }; repo_raw=${rest% *}
  [ "$repo_raw" != "$rest" ] || continue
  re_repo='^(~|/)[A-Za-z0-9._/@+ -]*$' re_commit='^[0-9a-f]{7,40}$' re_ref='^[A-Za-z0-9._][A-Za-z0-9._/-]*$'
  [[ $repo_raw =~ $re_repo ]] && [[ $commit =~ $re_commit ]] && [[ $ref =~ $re_ref ]] || continue
  case "$rel" in in|not-in) ;; *) continue ;; esac
  repo="${repo_raw/#\~/$HOME}"

  # Pages repeat the same claim; each distinct one is checked once.
  key="$repo_raw|$commit|$rel|$ref"
  cached=$(awk -F'\t' -v k="$key" '$1 == k { print $2 "\t" $3; exit }' "$cache")
  if [ -n "$cached" ]; then
    state=${cached%%$'\t'*} detail=${cached#*$'\t'}
  elif ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then state=NO-REPO detail="not a git repository on this machine"
  elif ! g rev-parse -q --verify "$commit^{commit}" >/dev/null 2>&1; then state=NO-COMMIT detail="commit unknown here"
  elif ! g rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1; then state=NO-REF detail="ref unknown here"
  else
    if g merge-base --is-ancestor "$commit" "$ref" 2>/dev/null; then contained=yes eq=""
    else eq=$(equivalent "$commit" "$ref"); [ -n "$eq" ] && contained=yes || contained=no
    fi
    tip=$(g log -1 --format='%h %cs' "$ref")
    case "$rel:$contained" in
      in:yes)     state=HOLDS detail="${eq:+as $eq, }$ref at $tip" ;;
      in:no)      state=STALE detail="not in $ref at $tip" ;;
      not-in:no)  state=HOLDS detail="$ref at $tip" ;;
      not-in:yes) state=STALE
                  # Where it arrived, not where the ref happens to point today.
                  at=$(arrival "$commit" "$ref") || at="$tip (ref tip; arrival not found)"
                  detail="now in $ref${eq:+ as $eq} at $at" ;;
    esac
  fi
  [ -n "$cached" ] || printf '%s\t%s\t%s\n' "$key" "$state" "$detail" >> "$cache"
  if $all || [ "$state" != HOLDS ]; then printf '%s\t%s\t%s\t%s\n' "$state" "$loc" "$marker" "$detail"; fi
done < <(grep -rnoE '\(verified [0-9]{4}-[0-9]{2}-[0-9]{2}: [^)]+\)' $wiki_dirs 2>/dev/null || true)
