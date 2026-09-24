#!/usr/bin/env bash
# Advisory scan for potentially contradictory, near-contemporaneous ticket status claims.
# Prints candidates only; semantic conflicts remain an agent/human judgment.
#
# The unit of comparison is a clause, not a line. A page states one fact per line with its
# citations attached, so the median line carrying a ticket id is 339 characters and often
# reports two actions at once ("merged to develop, never deployed to staging"). Comparing
# whole lines therefore either drowns in text that differs for unrelated reasons or, if the
# long ones are skipped, looks at a fraction of the vault. Splitting on clause boundaries and
# registering one entry per action verb keeps both the long lines and the per-action polarity.
set -euo pipefail
vp="${1:?usage: cross-page-claims.sh <vault-path>}"
cd "$vp"
dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sort)
[ -n "$dirs" ] || exit 0

find $dirs -maxdepth 1 -name '*.md' -print0 | xargs -0 awk '
BEGIN {
  na = split("deployed merged released executed ran fixed closed opened passed failed live", acts, " ")
  canon["ran"] = "executed"
}
function days(y, m, d, era, yoe, doy, mp) {
  y -= (m <= 2)
  era = int(y / 400)
  yoe = y - era * 400
  mp = m + (m > 2 ? -3 : 9)
  doy = int((153 * mp + 2) / 5) + d - 1
  return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
}
# Polarity belongs to the verb, not to the clause. A clause states more than one thing
# ("Until TASK-3616 fixed it, the generated client had not been regenerated"), and the
# negation can follow the verb as easily as precede it ("CI ran no .NET tests"), so the
# test is a window around the verb rather than the whole clause.
function polarity(s, verb,   before, after, win) {
  if (!match(s, "(^|[^a-z])" verb "([^a-z]|$)")) return "positive"
  before = RSTART - 30; if (before < 1) before = 1
  win = substr(s, before, RSTART - before + RLENGTH + 15)
  return (win ~ /(^|[^a-z])(not|never|no|no longer|hasn.t|haven.t|wasn.t|weren.t|didn.t|doesn.t|isn.t|aren.t|not-in|yet-to-be|not-yet)([^a-z]|$)/) ? "negative" : "positive"
}
# Whole words only: a substring test reports "delivered" as the action "live".
function wordin(s, w) { return s ~ ("(^|[^a-z])" w "([^a-z]|$)") }
function ticket(s, n, w, i) {
  n = split(s, w, /[^A-Za-z0-9_-]+/)
  for (i = 1; i <= n; i++) if (w[i] ~ /^[A-Za-z][A-Za-z0-9]+-[0-9]+$/) return toupper(w[i])
  return ""
}
function onedate(s, n, w, i, found, c) {
  n = split(s, w, /[^A-Za-z0-9_-]+/); c = 0
  for (i = 1; i <= n; i++) if (w[i] ~ /^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { found = w[i]; c++ }
  return c == 1 ? found : ""
}
function clean(s) {
  sub(/^[[:space:]]*[-*][[:space:]]+/, "", s)
  gsub(/\(→[^)]*\)/, "", s)
  gsub(/[[:space:]]+/, " ", s)
  return s
}
function trim(s) { sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
function record(id, path, file, text, day, act, stance,   k, j) {
  for (k = 1; k <= cnt[id]; k++)
    if (ePath[id, k] == path && eAct[id, k] == act && eSt[id, k] == stance) return
  if (cnt[id] == 0) ids[++nid] = id
  j = ++cnt[id]
  ePath[id, j] = path; eFile[id, j] = file; eText[id, j] = text
  eDay[id, j] = day; eAct[id, j] = act; eSt[id, j] = stance
}
{
  low = tolower($0)
  # Conflict entries quote what was said; a status pointer names the page that owns the status.
  if (low ~ /^- \[(open|resolved)/ || low ~ /status on[[:space:]]+\[\[/) next
  s = clean($0)
  line_id = ticket(s)
  if (line_id == "") next
  line_date = onedate(s)
  nc = split(s, cl, "; |: |—|–|\\. | but ")
  for (c = 1; c <= nc; c++) {
    clause = trim(cl[c])
    if (clause == "") continue
    lowc = tolower(clause)
    # A clause may inherit the ticket or the date from its line, but not both: a clause
    # carrying neither is not a dated status claim, it is prose that shares the sentence
    # with one. Inheriting both paired a general remark about the codegen script with six
    # unrelated pages, because the ticket and the date both came from elsewhere in the line.
    own_id = ticket(clause); own_date = onedate(clause)
    if (own_id == "" && own_date == "") continue
    id = (own_id != "") ? own_id : line_id
    date = (own_date != "") ? own_date : line_date
    if (date == "") continue
    split(date, p, "-")
    day = days(p[1], p[2], p[3])
    for (i = 1; i <= na; i++) {
      if (!wordin(lowc, acts[i])) continue
      a = (acts[i] in canon) ? canon[acts[i]] : acts[i]
      record(id, FILENAME, FILENAME ":" FNR, clause, day, a, polarity(lowc, acts[i]))
    }
  }
}
END {
  for (m = 1; m <= nid; m++) {
    id = ids[m]
    for (k = 1; k <= cnt[id]; k++) for (j = k + 1; j <= cnt[id]; j++) {
      if (ePath[id, k] == ePath[id, j]) continue
      if (eAct[id, k] != eAct[id, j] || eSt[id, k] == eSt[id, j]) continue
      d = eDay[id, k] - eDay[id, j]; if (d < 0) d = -d
      if (d > 3) continue
      printf "%s [%s] %s: %s <> %s: %s\n", id, eAct[id, k], eFile[id, k], eText[id, k], eFile[id, j], eText[id, j]
    }
  }
}
' 2>/dev/null | sort -u
