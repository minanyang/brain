#!/usr/bin/env bash
# search.sh [--vault <name>] [--cwd <dir>] [--max N] [--format tool|context] <query…>
#
# Ranks the vault's wiki pages against a query and prints the pages worth opening. This is the
# only implementation of the ranking: the registered `brain__search` tool shells out to it and
# so does the prompt hook, because the ranking has been changed three times on measured
# evidence and a second copy of it would be a seventh entry on the list in
# docs/architecture.md of things two versions must agree on. It is a shell script rather than
# part of the hooks module so that a host without the TypeScript engine can still retrieve.
#
# Scoring is BM25 with its usual constants. Nothing here calls a model.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WIKI_DIRS="me people projects decisions topics"
MAX=8
fmt=tool
require_rare=0
name="" cwd="$PWD" vault=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) name="$2"; shift ;;
    --cwd) cwd="$2"; shift ;;
    --max) MAX="$2"; shift ;;
    --format) fmt="$2"; shift ;;
    --require-rare-term) require_rare=1 ;;
    --vault-path) vault="$2"; shift ;;   # tests and callers that already resolved it
    --) shift; break ;;
    -*) printf 'search.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
query="$*"

if [ -z "$vault" ]; then
  config_exists || { echo 'No Brain vault covers this directory, so there is nothing to search.'; exit 0; }
  v=$(resolve_vault "$name" "$cwd" 2>/dev/null) || {
    echo 'No Brain vault covers this directory, so there is nothing to search.'; exit 0; }
  vault=$(vault_path "$v")
fi
[ -d "$vault" ] || { echo 'No Brain vault covers this directory, so there is nothing to search.'; exit 0; }

# Punctuation is a word boundary, which whitespace splitting alone does not know. Measured on
# a real question: `現在誰連得到 production 的 billingdb？` lost `billingdb` entirely, because the
# full-width question mark rode along and `billingdb？` is on no page — so a question ending in
# the user's own punctuation threw away its most distinctive term. Only punctuation is replaced,
# listed by codepoint: `- _ . / :` stay because identifiers contain them (`BILL-412`,
# `v0.6.13`, `topics/release-process`), letters outside ASCII stay because `café` is a word,
# and a script with its own punctuation is one more range here.
norm=$(printf '%s' "$query" | jq -Rr '
  # Ranges only, no literal punctuation in the comments: this whole program is one
  # single-quoted shell argument, so one apostrophe here ends it and the file stops parsing.
  def punct:
       (. >= 33 and . <= 44) or (. >= 59 and . <= 64)             # 21-2C and 3B-40 ASCII
    or (. >= 91 and . <= 94) or . == 96 or (. >= 123 and . <= 126) # 5B-5E, 60, 7B-7E ASCII
    or (. >= 8208 and . <= 8231) or (. >= 8240 and . <= 8286)      # 2010-2027, 2030-205E general
    or (. >= 12288 and . <= 12351)                                 # 3000-303F ideographic space and CJK
    or (. >= 65281 and . <= 65295) or (. >= 65306 and . <= 65312)  # FF01-FF0F, FF1A-FF20, minus the digits
    or (. >= 65339 and . <= 65344) or (. >= 65371 and . <= 65381); # FF3B-FF40, FF5B-FF65
  explode | map(if punct then 32 else . end) | implode' 2>/dev/null)
[ -n "$norm" ] && query="$norm"

# Terms: whitespace-separated, two characters or more, at most eight. A one-character term
# matches most of the vault and costs a grep, so it is dropped rather than searched.
terms=()
for t in $query; do
  [ "${#t}" -ge 2 ] || continue
  terms+=("$t")
  [ "${#terms[@]}" -ge 8 ] && break
done
if [ "${#terms[@]}" -eq 0 ]; then
  echo 'Give at least one search term of two characters or more.'
  exit 0
fi
first="${terms[0]}"

dirs=()
for d in $WIKI_DIRS; do [ -d "$vault/$d" ] && dirs+=("$vault/$d"); done
[ "${#dirs[@]}" -eq 0 ] && { echo 'No Brain vault covers this directory, so there is nothing to search.'; exit 0; }

work=$(mktemp -d "${TMPDIR:-/tmp}/brain-search.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT

# The page list. A page's own name is nowhere in its text, so a grep over contents alone
# answers the most obvious query with every page but the right one.
# Every sort and uniq in this script runs under LC_ALL=C, and that is not tidiness. BSD sort
# under en_US.UTF-8 gives CJK characters no collation weight, so it reports 不出, 人工, 出去 and
# 簡訊 as equal and uniq folds the four into one group of four — which took the bigram fallback
# below from working to returning nothing, because the folded group looked like a term on four
# pages and was filtered out as too common. LC_ALL=C compares bytes, which is what grouping by
# term needs. It is set per command rather than exported, because grep -i and tr need the real
# locale to case-fold anything outside ASCII.
find "${dirs[@]}" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort > "$work/pages"
[ -s "$work/pages" ] || { printf 'No page mentions "%s".\n' "$first"; exit 0; }

# Each page's `aliases:` line, in one grep over the whole vault rather than one per page: on a
# 190-page vault the per-page form is 190 processes before any term has been counted. The value
# is a YAML flow list, so the brackets, commas and quotes become spaces and what is left is
# matched exactly as the name is.
: > "$work/alias"
tr '\n' '\0' < "$work/pages" | xargs -0 grep -H -m1 '^aliases:' 2>/dev/null \
  | awk -F: '{ p = $1; sub(/^[^:]*:aliases:[[:space:]]*/, "", $0)
      a = tolower($0); gsub(/[][",]/, " ", a); gsub(/[[:space:]]+/, " ", a)
      sub(/^ /, "", a); sub(/ $/, "", a)
      if (a != "" && a != "[]") printf "%s\t%s\n", p, a }' > "$work/alias" || true

# One line per page: path, then the name as a reader means it — the slug, the slug with its
# separators spelled as spaces, so `cross-midnight-hours` answers "cross midnight" too, and any
# aliases the page declares, which are the vocabulary the page itself does not use.
awk -F'\t' -v v="$vault" '
  FILENAME == ARGV[1] { alias[$1] = $2; next }
  { slug = substr($0, length(v) + 2); sub(/\.md$/, "", slug)
    low = tolower(slug); flat = low; gsub(/[-\/]/, " ", flat)
    printf "%s\t%s %s%s\n", $0, low, flat, ($0 in alias ? " " alias[$0] : "") }
' "$work/alias" "$work/pages" > "$work/names"

# One grep per term, counting how often each page says it, plus the pages whose name carries
# it. A term in the page's own name is what the page is *about*, so it counts as two mentions
# the body would have had to repeat to earn; a page matched on its name alone is marked so the
# caller can say that its text does not repeat it.
count_terms() {  # count_terms <term…> → writes $work/tf and $work/byname
  : > "$work/tf.raw"
  : > "$work/names.hit"
  local t
  for t in "$@"; do
    # -F because a term is a literal, not a pattern: with punctuation now stripped a bracket
    # can no longer reach grep and kill the term silently, and `v0.6.13` should not match
    # `v0x6x13`.
    grep -ricF --include='*.md' -e "$t" "${dirs[@]}" 2>/dev/null \
      | awk -F: -v t="$t" '$NF > 0 { c = $NF; sub(/:[0-9]+$/, ""); printf "%s\t%s\t%s\n", $0, t, c }' \
      >> "$work/tf.raw" || true
    awk -F'\t' -v t="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')" \
      'index($2, t) > 0 { printf "%s\t%s\n", $1, t }' "$work/names" >> "$work/names.hit"
  done
  # Fold the name hits into the counts: +2 per term, and a page with no text count for that
  # term is recorded as a name-only match.
  awk -F'\t' '
    FILENAME == ARGV[1] { text[$1 SUBSEP $2] = $3; next }
    { key = $1 SUBSEP $2
      if (!(key in text)) byname[$1] = 1
      text[key] = (key in text ? text[key] : 0) + 2 }
    END { for (k in text) { split(k, a, SUBSEP); printf "%s\t%s\t%s\n", a[1], a[2], text[k] }
          for (p in byname) printf "%s\n", p > "/dev/stderr" }
  ' "$work/tf.raw" "$work/names.hit" > "$work/tf" 2> "$work/byname"
}
count_terms "${terms[@]}"

# The fallback for a script with no word boundaries. A Mandarin, Japanese or Thai question
# written without spaces is one whitespace token, so it greps as one long literal and matches
# nothing: "訂位超收是怎麼發生的？" returned zero candidates against a 190-page vault. Character
# bigrams are the standard answer (it is what Lucene's CJK analyser does), and the measured
# shape of it is narrow on purpose.
#
# The trigger is **zero candidates**, not "no rare term". Measured on 2026-10-18 against a real
# vault: triggering on the absence of a rare identifier instead took a question that was
# answered at rank 9 down to rank 43, because it fired on questions that were already working.
# On the zero-candidate trigger the fallback fired on 3 of 7 real questions, changed nothing
# that already had candidates, and moved 訂位超收 from absent to rank 1 of 11, 人工審核的簡訊
# from absent to 8 of 26, and 資料庫不要外鍵 from absent to 4 of 42.
#
# Unfiltered bigrams make it worse, also measured: 13 fragments of Mandarin function words
# (現在/得到/有沒/沒有) outnumbered the 2 English terms in one question and took it from rank 4
# to 40. So a bigram is kept only if it is on a fifth or less of the vault. That ceiling is on
# the bigrams alone — applied to the ASCII terms too it dropped `production` and took the same
# question to absent, because BM25's own idf already handles a term that everything carries.
if [ ! -s "$work/tf" ]; then
  bigrams=$(printf '%s' "$query" | jq -Rr '
    # jq has no hex literals, so the ranges are decimal with their usual names beside them.
    # A further script without word boundaries is one more line here.
    def iscjk: (. >= 12352 and . <= 12543)     # 3040-30FF hiragana, katakana
      or (. >= 13312 and . <= 19903)           # 3400-4DBF CJK extension A
      or (. >= 19968 and . <= 40959)           # 4E00-9FFF CJK unified
      or (. >= 63744 and . <= 64255)           # F900-FAFF CJK compatibility
      or (. >= 3584 and . <= 3711);            # 0E00-0E7F Thai
    explode | map(if iscjk then . else 32 end) | implode
    | split(" ") | map(select(length >= 2))
    | map(. as $s | [range(0; ($s | length) - 1) | $s[.:(. + 2)]])
    | flatten | unique | .[]' 2>/dev/null)
  if [ -n "$bigrams" ]; then
    bg=()
    while IFS= read -r b; do [ -n "$b" ] && bg+=("$b"); done <<EOF
$bigrams
EOF
    if [ "${#bg[@]}" -gt 0 ]; then
      count_terms "${bg[@]}"
      # Drop the bigrams a fifth or more of the vault carries — the function-word fragments —
      # and keep the ranking to the ones that can discriminate.
      cap=$(( $(wc -l < "$work/pages" | tr -d ' ') / 5 )); [ "$cap" -lt 1 ] && cap=1
      cut -f2 "$work/tf" | LC_ALL=C sort | LC_ALL=C uniq -c \
        | awk -v c="$cap" '$1 <= c { print $2 }' | LC_ALL=C sort > "$work/bg.keep"
      # An empty keep list has to short-circuit: `NR == FNR` reads the first record of the
      # *second* file as the first file when the first one is empty, so the filter would keep
      # whatever that row happened to name. Nothing surviving means no bigram discriminates,
      # which is answered by leaving tf empty and saying so below.
      if [ -s "$work/bg.keep" ]; then
        awk -F'\t' 'NR == FNR { k[$1]; next } $2 in k' "$work/bg.keep" "$work/tf" > "$work/tf.keep"
        mv "$work/tf.keep" "$work/tf"
        bgterms=()
        while IFS= read -r b; do [ -n "$b" ] && bgterms+=("$b"); done < "$work/bg.keep"
        # The original terms are kept when nothing survived, so the "no page mentions" line
        # below still names what the user actually asked for.
        if [ "${#bgterms[@]}" -gt 0 ]; then terms=("${bgterms[@]}"); first="${terms[0]}"; fi
      else
        : > "$work/tf"
      fi
    fi
  fi
fi

[ -s "$work/tf" ] || {
  printf 'No page mentions'
  for t in "${terms[@]}"; do printf ' "%s" or' "$t"; done | sed 's/ or$//'
  printf '.\n'
  exit 0
}

# Page length, so that repetition on a short page about the subject outranks one mention
# apiece on a long page that touches everything.
tr '\n' '\0' < "$work/pages" | xargs -0 wc -c 2>/dev/null \
  | awk '$2 != "total" && NF >= 2 { n = $1; $1 = ""; sub(/^ /, ""); printf "%s\t%s\n", $0, (n < 1 ? 1 : n) }' \
  > "$work/sizes"

# BM25: a term on most pages separates nothing, a repeated term counts with diminishing
# return, and the length divisor is what keeps the long pages honest. The tie-break is the
# name hit before the path, because the page *called* X answers "X" better than one linking
# to it.
awk -F'\t' -v nterms="${#terms[@]}" '
  FILENAME == ARGV[1] { size[$1] = $2; total++; sum += $2; next }
  FILENAME == ARGV[2] { byname[$1] = 1; next }
  { tf[$1 SUBSEP $2] = $3; seen[$1] = 1; df[$2]++; if (!($1 SUBSEP $2 in once)) { once[$1 SUBSEP $2] = 1; matched[$1]++ } }
  END {
    avg = (total > 0 ? sum / total : 1)
    if (avg <= 0) avg = 1
    K1 = 1.2; B = 0.75
    n = 0
    for (p in seen) {
      s = 0
      for (k in tf) {
        split(k, a, SUBSEP)
        if (a[1] != p) continue
        d = (df[a[2]] > 0 ? df[a[2]] : 1)
        idf = log(1 + (total - d + 0.5) / (d + 0.5))
        len = (p in size ? size[p] : avg)
        s += idf * tf[k] * (K1 + 1) / (tf[k] + K1 * (1 - B + B * len / avg))
      }
      n++
      printf "%.9f\t%d\t%d\t%s\n", s, (p in byname ? 1 : 0), matched[p], p
    }
    printf "%d\n", n > "/dev/stderr"
  }
' "$work/sizes" "$work/byname" "$work/tf" 2> "$work/count" \
  | LC_ALL=C sort -t"$(printf '\t')" -k1,1gr -k2,2nr -k4,4 > "$work/ranked"

found=$(cat "$work/count" 2>/dev/null || echo 0)
shown=$(( found < MAX ? found : MAX ))
pages=$(wc -l < "$work/pages" | tr -d ' ')

# Which matched term is rare, and which is the rarest. Document frequency is already what BM25
# weights by, so this changes no score; it decides two other things.
#
# The quoted lines are grepped for the rarest matched term rather than the query's first word.
# Keyed on the first word, "why did the reconciler double count" quotes the lines that say
# `why` — which is none of them — so the page arrived with its name, its lead and no evidence.
#
# And `--require-rare-term` is the floor for an injection nobody asked for: with no rare term,
# the best page is whatever happened to carry `the`. Measured on a real question — "how does
# the kafka consumer group rebalance itself on restart", about a subject the vault has never
# held — the result was a page matching 1 of 8 terms, and it would have been pushed in front of
# the agent as the vault's answer. The floor is not applied to the registered tool: when
# somebody asked, a weak answer still beats silence, and they can see how weak it is.
rare_cap=$(( pages / 5 ))
[ "$rare_cap" -lt 1 ] && rare_cap=1
cut -f2 "$work/tf" | LC_ALL=C sort | LC_ALL=C uniq -c | awk '{printf "%s\t%s\n", $2, $1}' > "$work/df"
# Under ten pages document frequency says nothing — every term is on most of the vault — so
# every term counts as rare rather than none of them.
if [ "$pages" -lt 10 ]; then
  rare=$(cut -f1 "$work/df")
else
  rare=$(awk -F'\t' -v c="$rare_cap" '$2 <= c { print $1 }' "$work/df")
fi
if [ -n "$rare" ]; then
  # The rarest matched term, which is what the quoted lines are grepped for. `sort -k1,1n`
  # orders by document frequency; among equals the first in df order wins, which is stable
  # because df is written in the order the terms were counted, which is query order.
  lowest=$(awk -F'\t' '{ print $2 "\t" $1 }' "$work/df" | LC_ALL=C sort -k1,1n | head -1 | cut -f2)
  [ -n "$lowest" ] && first="$lowest"
elif [ "$require_rare" = 1 ]; then
  exit 0
fi

# Under the same flag, a page that matched no rare term is dropped rather than listed. The
# floor above only decided whether to answer at all; without this, the answer to a question
# with one rare term in it was the right page followed by every page in the vault carrying
# `the`, which teaches the reader that the vault is noise.
#
# It is deliberately not the registered tool's behaviour. Filtering *terms* by document
# frequency was measured on 2026-10-18 to be harmful — it dropped `production` and took a page
# that answered a real question from rank 9 to absent. A page filter is not that, and against
# scripts/test-search-ranking.sh it moved no rank at all: all fourteen questions landed exactly
# where they had, and what it removed was the pages below the answer that carried only a common
# term. But that fixture is fabricated, so this is evidence that the filter is harmless on a
# corpus built by the same hand, not that it is harmless on a vault. It stays on the path whose
# cost is bounded — one injection nobody asked for — until it has been run against a real one.
if [ "$require_rare" = 1 ]; then
  printf '%s\n' "$rare" | awk 'NF' | LC_ALL=C sort > "$work/rare"
  awk -F'\t' 'NR == FNR { r[$1]; next } $2 in r { print $1 }' "$work/rare" "$work/tf" \
    | LC_ALL=C sort -u > "$work/rarepages"
  awk -F'\t' 'NR == FNR { p[$1]; next } $4 in p' "$work/rarepages" "$work/ranked" > "$work/ranked.f"
  mv "$work/ranked.f" "$work/ranked"
  found=$(wc -l < "$work/ranked" | tr -d ' ')
  [ "$found" -gt 0 ] || exit 0
  shown=$(( found < MAX ? found : MAX ))
fi

lead() {  # the first paragraph after the frontmatter: the line that says whether to open it
  sed '1{/^---$/!q;};1,/^---$/d' "$1" 2>/dev/null \
    | awk 'NF { buf = buf " " $0; next } buf { print substr(buf, 2); done = 1; exit } END { if (buf && !done) print substr(buf, 2) }'
}

# `pointer` is the cheapest honest answer: the page addresses and nothing else. It exists for
# the prompt hook's budget ladder — a result that does not fit is degraded to addresses rather
# than truncated, because a page quoted halfway through reads as the whole of what the page
# says. The sentence telling the reader not to invent a path is the point of the format: an
# address with no excerpt beside it is the shape a model will happily complete from memory.
if [ "$fmt" = pointer ]; then
  printf 'Brain vault pages about this, highest first. Open one by its path under the vault; do not guess a path that is not listed.\n'
  i=0
  while IFS="$(printf '\t')" read -r _score _named _matched path; do
    i=$((i + 1)); [ "$i" -gt "$MAX" ] && break
    page=${path#"$vault"/}; page=${page%.md}
    printf -- '- [[%s]]\n' "$page"
  done < "$work/ranked"
  exit 0
fi

if [ "$fmt" = context ]; then
  printf 'Brain vault pages that match this question, highest first. Read one before stating facts about what it covers.\n'
else
  printf 'The %d best of %d pages that mention any of these terms, highest first. Read one in full before stating facts about what it covers.\n' \
    "$shown" "$found"
fi

i=0
while IFS="$(printf '\t')" read -r _score named matched path; do
  i=$((i + 1)); [ "$i" -gt "$MAX" ] && break
  page=${path#"$vault"/}; page=${page%.md}
  printf '\n## [[%s]]  (%s/%s terms)\n' "$page" "$matched" "${#terms[@]}"
  [ "$fmt" = context ] || printf '%s\n' "$(lead "$path")"
  ex=$(grep -inF -m 3 -e "$first" "$path" 2>/dev/null | cut -c1-300 | sed 's/^/  /')
  if [ -n "$ex" ]; then
    printf '%s\n' "$ex"
  elif [ "$named" = 1 ]; then
    printf "  (matched on the page's name or an alias; its text does not repeat it)\n"
  fi
done < "$work/ranked"

[ "$found" -gt "$MAX" ] && printf '\n(%d further pages matched.)\n' "$((found - MAX))"
exit 0
