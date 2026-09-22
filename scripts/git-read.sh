#!/usr/bin/env bash
# git-read.sh <repo-dir> <subcommand> [args...] — read-only git for an agent that must
# not be able to write or run a program through git.
#
# A permission pattern such as `Bash(git -C * log *)` is not enough: the wildcard before
# the subcommand also admits `-c core.pager=<cmd>` or `--exec-path`, both of which run an
# arbitrary program. Here the repository and the subcommand are separate arguments, only
# subcommands that read history are allowed, and the options that write a file or launch a
# program are refused. `status` is left out because it runs a repository's fsmonitor hook.
#
# It guards the arguments, not the repository: a repository's own config is trusted, as it
# is by plain git. Point it at your own checkouts.
set -u
usage="usage: git-read.sh <repo-dir> <subcommand> [args...]"
repo="${1:?$usage}" sub="${2:?$usage}"
shift 2

die() { printf 'git-read: %s\n' "$*" >&2; exit 2; }

repo=$(cd "$repo" 2>/dev/null && pwd -P) || die "no such directory"
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $repo"

case "$sub" in
  log|show|merge-base|rev-parse|rev-list|cat-file|ls-tree|ls-files|grep|blame|describe|shortlog|for-each-ref|diff) ;;
  *) die "subcommand not allowed: $sub" ;;
esac

for a in "$@"; do
  case "$a" in
    --output|--output=*|-O|-O*|--open-files-in-pager|--open-files-in-pager=*|\
    --ext-diff|--textconv|--filters|--exec-path|--exec-path=*|--upload-pack*|--receive-pack*|\
    -c|--config-env*|--git-dir*|--work-tree*|--namespace*|--no-index)
      die "option not allowed: $a" ;;
  esac
done

export GIT_PAGER=cat PAGER=cat GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
exec git --no-pager -C "$repo" "$sub" "$@"
