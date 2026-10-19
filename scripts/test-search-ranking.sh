#!/usr/bin/env bash
# test-search-ranking.sh — a frozen fixture for search.sh, on a generated throwaway vault.
#
# Why a fixture and not more assertions: the ranking has been changed three times on measured
# evidence (0.6.5 name hits, 0.6.7 BM25, 0.6.10 the match count) and each measurement was a
# hand-run against a real vault, so nothing in the repository could tell whether the next
# change made retrieval worse. The per-question baselines below are that missing instrument.
#
# What it is NOT: evidence that the ranking is good. The corpus and the questions are both
# fabricated, so a question's gold page is gold by construction. The value is that a change
# which moves any rank shows up in a diff before it ships, and that anyone can reproduce the
# numbers with no vault, no key and no judge. Read as a quality score it would be the kind of
# benchmark that flatters, which is a floor that never trips.
#
# The corpus is generated rather than mocked, because a mock of grep is not grep: an earlier
# version of this fixture matched terms exactly and so disagreed with the real thing twice over
# — `grep -c` counts matching *lines* rather than occurrences, and a term matches as a
# substring, which is how `do` scores a page named `reconciler-double-count`.
#
# Every name, term and ticket id is invented. Fabricated ticket ids are three digits, because
# check.sh assumes a longer one came from a real vault.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v="$(mktemp -d)"
# Every throwaway vault this makes, so a mechanism case below leaves none behind.
vaults="$v"
trap 'for d in $vaults; do rm -r -f "$d"; done' EXIT

# page <slug> <pad-lines> <term:lines…> — `grep -c` counts lines, so a term wanted n times is
# written on n lines of its own. The pad is term-free filler that sets the page's length,
# which is what the BM25 divisor normalises against.
page() {
  local slug="$1" pad="$2"; shift 2
  local f="$v/$slug.md" i t n
  mkdir -p "$(dirname "$f")"
  { printf -- '---\ntitle: %s\ntype: topic\n---\n\n' "${slug##*/}"
    printf 'A fabricated page in the acme-billing vault.\n\n'
    for spec in "$@"; do
      t="${spec%%:*}"; n="${spec##*:}"
      i=0; while [ "$i" -lt "$n" ]; do printf 'This line is about %s and what it covers.\n' "$t"; i=$((i + 1)); done
    done
    i=0; while [ "$i" -lt "$pad" ]; do printf 'Filler prose with no searchable subject in it whatsoever.\n'; i=$((i + 1)); done
  } > "$f"
}

# The pages a question turns on. Each exists to put one ranking decision under load.
page topics/invoice-rounding            4  bill-412:2 rounding:6 cents:4 invoice:5 production:1
# The page that touches everything, at ten times the length of a page about one subject.
# Before 0.6.7 a page like this took the top of every result, because it matched the most terms.
page projects/acme-billing            380  invoice:3 reconciler:2 ledger:2 payout:2 settlement:1 \
                                           rounding:1 cents:1 retry:2 backoff:1 worker:2 webhook:1 \
                                           replay:1 dunning:1 production:4 deploy:3 staging:2 \
                                           release:2 schema:1 migration:1 refund:1 bill-412:1
# The 0.6.7 case: `production` is on every page, so only the rare terms separate anything.
page topics/reconciler-double-count     8  reconciler:7 ledger:4 production:2 invoice:1
# A page whose text never writes its own name — the 0.6.5 defect. Neither `version` nor
# `train` appears in its body, so it can only be reached through the page list.
page topics/version-train               6  release:3 staging:2 deploy:2
page topics/payout-settlement           6  payout:6 settlement:5 ledger:1 production:1
page decisions/2026-08-14-invoice-worker-retries-with-backoff 6 retry:6 backoff:5 worker:4 invoice:2 production:1
page topics/webhook-replay              5  webhook:5 replay:4 retry:1 production:1
# The disambiguation pair: both pages are about replaying something.
page topics/manual-invoice-replay       6  invoice:6 replay:5 worker:2 ledger:1
page topics/dunning-schedule            5  dunning:6 invoice:2 refund:1
# A page that mentions a subject in passing, to stand against the page about it.
page people/platform-team               3  reconciler:1 deploy:1 production:1
page topics/release-process             8  release:7 deploy:6 staging:4 production:3
page topics/schema-migrations           7  schema:6 migration:5 deploy:1 production:1

# Filler, so document frequency and the average page length are a vault's rather than a
# dozen pages'. Every one carries `production`, which is what makes `production` unable to
# separate anything.
filler_terms="deploy invoice ledger release worker schema refund"
i=1
while [ "$i" -le 28 ]; do
  set -- $filler_terms
  eval "mid=\${$(( (i % 7) + 1 ))}"
  page "topics/filler-$(printf '%02d' "$i")" "$(( 3 + i % 7 ))" "production:$(( 1 + i % 3 ))" "$mid:$(( 1 + i % 2 ))"
  i=$((i + 1))
done

# Two pages declare an alias, which is the one field written for the search rather than the
# reader: the vocabulary a question is likely to use and the page does not. The two questions
# below that these answer were recorded as misses before the field existed, and their baselines
# are what the field changed.
alias_for() {  # alias_for <slug> <aliases…>
  local slug="$1"; shift
  local list; list=$(printf '%s, ' "$@"); list=${list%, }
  sed -i '' "s|^type: topic\$|type: topic\\naliases: [$list]|" "$v/$slug.md"
}
alias_for topics/reconciler-double-count 'counted twice' 'double counting'
alias_for topics/release-process 'shipping changes' 'rollout'

pages=$(find "$v" -name '*.md' | wc -l | tr -d ' ')

# rank <gold> <query…> → the gold page's 1-based position, or "absent".
rank() {
  local gold="$1"; shift
  "$here/search.sh" --vault-path "$v" "$@" \
    | awk -v g="$gold" '/^## \[\[/ { n++; p = $0; sub(/^## \[\[/, "", p); sub(/\]\].*$/, "", p)
        if (p == g && !found) { at = n; found = 1 } }
      END { print (found ? at : "absent") }'
}

# Each row is: baseline | gold | trap | query. The baseline was read off a run, never
# predicted — a guessed baseline asserts the author's belief instead of the behaviour, and the
# first two written here were both wrong.
pass=0 fail=0 improved=0 found=0
recip=0
report=""

check() {  # check <baseline> <gold> <trap> <query…>
  local base="$1" gold="$2" trap_="$3"; shift 3
  local got; got=$(rank "$gold" "$@")
  [ "$got" != absent ] && { found=$((found + 1)); recip=$(awk -v r="$recip" -v g="$got" 'BEGIN{printf "%.6f", r + 1/g}'); }
  report="${report}  $(printf '%-7s' "$got")(was $(printf '%-7s' "$base")) $*
"
  if [ "$base" = absent ]; then
    if [ "$got" = absent ]; then pass=$((pass + 1))
    else improved=$((improved + 1)); printf '  IMPROVED %s → %s: was absent, now #%s — update the baseline\n' "$*" "$gold" "$got" >&2; fi
  elif [ "$got" = absent ] || [ "$got" -gt "$base" ]; then
    fail=$((fail + 1)); printf '  WORSE %s → %s: baseline #%s, got %s\n' "$*" "$gold" "$base" "$got" >&2
  elif [ "$got" -lt "$base" ]; then
    improved=$((improved + 1)); printf '  IMPROVED %s → %s: baseline #%s, now #%s — update the baseline\n' "$*" "$gold" "$base" "$got" >&2
  else pass=$((pass + 1)); fi
}

check 1 topics/invoice-rounding 'a rare identifier beside a topic term — the easiest case, and the one that must never regress' BILL-412 rounding
check 1 topics/reconciler-double-count 'one term is on every page, so only the two rare terms separate anything (the 0.6.7 defect)' production reconciler ledger
check 1 topics/version-train "the page's text never writes its own name (the 0.6.5 defect)" version train
check 1 topics/invoice-rounding 'a page ten times longer carries both terms too, so the length divisor decides it' invoice cents
check 1 topics/manual-invoice-replay 'two pages are about replaying something; only the term balance says which subject' invoice replay
check 1 decisions/2026-08-14-invoice-worker-retries-with-backoff 'the gold page is in decisions/, which sorts before topics/, so a tie would hide a scoring bug' retry backoff worker
check 1 topics/payout-settlement 'both terms are rare and on one page — the case every ranking gets right' payout settlement
check 1 topics/dunning-schedule 'a single rare term where the name and the text agree' dunning
check 1 topics/webhook-replay 'a competing page says replay more often, so the rarer term has to carry it' webhook replay
check 1 topics/schema-migrations 'the name is plural and the query singular, so the name match is a substring one' schema migration staging
check 1 topics/reconciler-double-count 'a page mentioning the subject once stands against the page about it' reconciler
# Expected misses. They are here so the fixture cannot be passed by a ranking that handles
# only the winnable cases, and so a change that happens to fix one is reported rather than
# absorbed. A fixture of winnable questions is a floor that never trips.
check absent topics/reconciler-double-count 'EXPECTED MISS: one term, on all 40 pages — nothing can separate this' production
# Vocabulary mismatch: the right page shares no word with the question. This is the class that
# fails on a real vault, and the before-and-after for a second retrieval signal — a bigram
# fallback for a query whose terms return nothing, and a page's own `aliases:` line.
check 1 topics/reconciler-double-count 'vocabulary mismatch: no word of the question is in the page or its name — answered only by the page declaring `counted twice` as an alias, which is what that field is for' invoices counted twice
check 1 topics/release-process "a paraphrase sharing no word with the page's subject, answered by its alias and by nothing else in the ranking" shipping changes safely

# Printed on every run, per question, because an aggregate hides the mechanism: a documented
# case in this field moved +0.070 overall while one category inside it moved +0.239.
total=$((pass + fail + improved))
printf 'search ranking fixture: %s pages, %s questions\n%s' "$pages" "$total" "$report"
awk -v f="$found" -v t="$total" -v r="$recip" 'BEGIN { printf "  recall@8 %.3f   MRR %.3f\n", f/t, r/t }'



# A fixture of winnable questions is a floor that never trips, so at least one question must
# still be a known miss. Two of the three became hits when `aliases:` landed, which is the
# fixture doing its job; the day the last one does, this fails and asks for a harder question
# rather than quietly reporting a perfect score.
mpass=0 mfail=0
misses=$(grep -c "^check absent " "$here/test-search-ranking.sh")
if [ "$misses" -ge 1 ]; then
  printf '  ok the fixture still holds %s question(s) it is expected to fail\n' "$misses"
  mpass=$((mpass + 1))
else
  fail=$((fail + 1))
  printf '  FAIL the fixture has no expected miss left — add a harder question\n' >&2
fi

# ---------------------------------------------------------------------------------------
# Mechanisms. Each is a defect the ranking once had, on a vault small enough that only the
# one decision under test can explain the order. These were assertions in hooks/search.test.ts
# against a mock of grep; they are here now because the mock disagreed with grep.
# ---------------------------------------------------------------------------------------
m() { if [ "$2" = "$3" ]; then mpass=$((mpass + 1)); printf '  ok %s\n' "$1"; else mfail=$((mfail + 1)); printf '  FAIL %s — expected %s, got %s\n' "$1" "$3" "$2" >&2; fi; }

mech() {  # mech <query…> → prints the ranked slugs, one per line
  "$here/search.sh" --vault-path "$w" "$@" | sed -n 's/^## \[\[\(.*\)\]\].*/\1/p'
}
newvault() { w="$(mktemp -d)"; vaults="$vaults $w"; }
mpage() {  # mpage <slug> <pad> <term:lines…>
  local slug="$1" pad="$2"; shift 2
  local f="$w/$slug.md" i t n
  mkdir -p "$(dirname "$f")"
  { printf -- '---\ntitle: %s\ntype: topic\n---\n\nA lead line.\n\n' "${slug##*/}"
    for spec in "$@"; do t="${spec%%:*}"; n="${spec##*:}"
      i=0; while [ "$i" -lt "$n" ]; do printf 'A line about %s here.\n' "$t"; i=$((i + 1)); done; done
    i=0; while [ "$i" -lt "$pad" ]; do printf 'Filler prose with no subject at all.\n'; i=$((i + 1)); done
  } > "$f"
}

# A page that keeps saying the term outranks one that mentions it in passing.
newvault; mpage topics/alpha 0 rounding:1; mpage topics/zulu 0 rounding:9
m "repetition outranks a passing mention" "$(mech rounding | head -1)" "topics/zulu"

# A long page does not outrank a short one on bulk alone: the length divisor is what keeps a
# page that touches everything off the top of every result.
newvault; mpage topics/alpha 400 rounding:4; mpage topics/zulu 0 rounding:4
m "length normalisation decides equal counts" "$(mech rounding | head -1)" "topics/zulu"

# A term nearly every page carries does not decide the order. Before 0.6.7 the tie fell to the
# path, which sorts topics/ last, so the directory holding most of a vault could not place.
newvault
mpage topics/alpha 0 production:1 ingress:1
mpage topics/beta  0 production:1 ingress:1
mpage topics/zulu  0 production:1 ingress:7
m "a near-universal term does not decide the order" "$(mech production ingress | head -1)" "topics/zulu"

# A page is found by its own name, which its text does not repeat — the 0.6.5 defect.
newvault; mpage topics/version-train 0 release:2; mpage topics/other 0 release:9
m "a page is found by its own name" "$(mech version train | head -1)" "topics/version-train"

# The page called X answers "X" better than one that merely links to it, so a name hit breaks
# a tie before the path does.
newvault; mpage topics/reconciler 0 ledger:1; mpage topics/aaa-links-here 0 reconciler:1 ledger:1
m "a name hit breaks the tie before the path" "$(mech reconciler | head -1)" "topics/reconciler"

# A term is one term however the asker capitalised it. The name hit was labelled with the
# lowercased term while the text count kept the term as typed, so a page matching both ways
# carried two rows for one term: it counted twice toward coverage, scored twice, and split its
# own document frequency. Every question here and every page name is lowercase, which is why
# the fixture never showed it — so this one asks in the capitalisation a person would use.
newvault; mpage topics/reconciler 0 reconciler:3
m "a term is one term however it was capitalised" \
  "$("$here/search.sh" --vault-path "$w" Reconciler | sed -n 's/.*(\([0-9]*\/[0-9]*\) terms)/\1/p' | head -1)" \
  "1/1"



# ---------------------------------------------------------------------------------------
# The fallback for scripts with no word boundaries. Kept out of the frozen baselines above so
# that adding it did not move them: these are mechanism assertions on their own vaults.
#
# Written as Mandarin because that is what the measurement was run in, but nothing here is
# about Mandarin. A question in any script without spaces greps as one long literal and matches
# nothing, and the fix is character bigrams — what Lucene's CJK analyser does. Japanese and Thai
# go through the same path; a further script is one more codepoint range in search.sh.
# ---------------------------------------------------------------------------------------
cjkvault() {
  newvault
  mkdir -p "$w/topics"
  printf -- '---\ntitle: Overbooking\ntype: topic\n---\n\n訂位超收的成因與處理。\n\n一行關於訂位超收的說明。\n一行關於超收上限的說明。\n' > "$w/topics/overbooking.md"
  printf -- '---\ntitle: SMS routing\ntype: topic\n---\n\n簡訊送不出去的原因。\n\n一行關於人工審核的說明。\n一行關於簡訊路由的說明。\n' > "$w/topics/sms-routing.md"
  printf -- '---\ntitle: No foreign keys\ntype: topic\n---\n\n資料庫不要外鍵的決定。\n\n一行關於外鍵的說明。\n' > "$w/topics/no-foreign-keys.md"
  printf -- '---\ntitle: Prod db access\ntype: topic\n---\n\n誰連得到 production 的 billingdb。\n\n一行關於 billingdb 的說明。\n' > "$w/topics/prod-db-access.md"
  # Function-word noise on most of the vault, so the bigrams 現在 and 得到 are too common to
  # rank with. Unfiltered bigrams were measured to make ranking worse, not better: thirteen
  # fragments of function words outnumbered the two English terms in one real question and
  # took it from rank 4 to rank 40.
  local i=1
  while [ "$i" -le 14 ]; do
    printf -- '---\ntitle: F%s\ntype: topic\n---\n\n現在的狀況說明。\n\n一行關於部署的說明。\n我們現在沒有得到結果。\n' "$i" \
      > "$w/topics/filler-$i.md"
    i=$((i + 1))
  done
}

# Every default page type has to be in search.sh's WIKI_DIRS, and that list is hardcoded: a type
# added to the schema and forgotten there is a whole directory the search cannot see, with no
# symptom but an answer that is not in the results. One page per directory is enough to catch it.
newvault
for d in me people projects decisions topics procedures; do
  mkdir -p "$w/$d"
  printf -- '---\ntitle: T\ntype: topic\n---\n\nA lead.\n\nA line about zebracrossing here.\n' > "$w/$d/probe.md"
done
found=$(mech zebracrossing | wc -l | tr -d ' ')
m "every default page directory is searched" "$found" "6"

cjkvault
m "a Mandarin question with no spaces finds its page" "$(mech '訂位超收是怎麼發生的？' | head -1)" "topics/overbooking"
m "and so does a longer one" "$(mech '為什麼走人工審核的簡訊會送不出去' | head -1)" "topics/sms-routing"
m "and one whose subject is a decision" "$(mech '我們為什麼決定資料庫不要外鍵？' | head -1)" "topics/no-foreign-keys"

# The property the whole design rests on: the trigger is zero candidates, so a question whose
# ASCII terms already match must come back exactly as it would have. Triggering on "no rare
# identifier" instead was measured to take a question answered at rank 9 down to rank 43.
m "a mixed question is decided by its identifiers, not by bigrams" \
  "$(mech '現在誰連得到 production 的 billingdb？' | head -1)" "topics/prod-db-access"
m "and the fallback leaves a pure-ASCII question alone" "$(mech billingdb | head -1)" "topics/prod-db-access"

# Punctuation is a word boundary. Before this, the full-width question mark rode along on the
# most distinctive term in the question and `billingdb？` was on no page.
m "a term is not lost to the punctuation beside it" \
  "$("$here/search.sh" --vault-path "$w" -- '用的是 billingdb？' | sed -n 's/^## \[\[\(.*\)\]\].*/\1/p' | head -1)" \
  "topics/prod-db-access"

# A question the vault has nothing about must still say so, naming what was asked rather than
# the bigrams it tried.
case "$("$here/search.sh" --vault-path "$w" -- '京都的拉麵店推薦' 2>&1)" in
  *'No page mentions'*) m "a subject the vault lacks is said plainly" ok ok ;;
  *) m "a subject the vault lacks is said plainly" "unexpected output" ok ;;
esac

# A failed mechanism assertion is counted apart from a ranking regression. Printing both under
# `worse` read as "retrieval got worse", which is the one thing this script exists to say
# without ambiguity, and it misled its own author on 2026-10-19.
printf 'test-search-ranking: %d at baseline, %d worse, %d improved, %d mechanisms ok, %d mechanisms failed\n' \
  "$pass" "$fail" "$improved" "$mpass" "$mfail"
[ "$fail" = 0 ] && [ "$mfail" = 0 ]
