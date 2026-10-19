// A frozen corpus and question set for the vault search ranking, with no model call anywhere.
//
// What this is for: ranking is the one part of Brain whose behaviour has been changed on
// measured evidence several times (0.6.5 name hits, 0.6.7 BM25, 0.6.10 the match count), and
// every one of those measurements cost a hand-run against a real vault. Nothing in the
// repository could tell whether the next change made ranking worse, because the unit tests in
// search.test.ts assert mechanisms — a long page must not win on bulk — and a mechanism can
// hold while the order a reader actually gets falls apart.
//
// What it is NOT: evidence that the ranking is good. The corpus is fabricated and so are the
// questions, so a question's gold page is gold by construction. The fixture freezes the rank
// each question currently gets; its value is that a change which moves any of them is visible
// in a diff before it ships, and that anyone can reproduce the numbers without a vault, an API
// key or a judge. Reading it as a quality score would make it the kind of benchmark that
// flatters, which is a floor that never trips.
//
// Every name, term and ticket id here is invented. Fabricated ticket ids are three digits,
// because check.sh assumes a longer one came from a real vault.

export const VAULT = '/home/t/acme-billing'

type Page = {
  // How often the page's text says each term. A term absent here is absent from the page.
  terms: Record<string, number>
  // Bytes, which is what the length divisor in BM25 normalises against.
  size: number
}

// The pages a question turns on. Each exists to put one ranking decision under load.
const NAMED: Record<string, Page> = {
  // The subject of the rare-identifier question, and the short page that must beat the long
  // one that merely also carries both its terms.
  'topics/invoice-rounding': {
    terms: { 'bill-412': 2, rounding: 6, cents: 4, invoice: 5, production: 1 },
    size: 2600,
  },
  // The page that touches everything: it carries nearly every term once and is ten times the
  // length of a page about one subject. Before 0.6.7 a page like this took the top of every
  // result, because it matched the most terms.
  'projects/acme-billing': {
    terms: {
      invoice: 3, reconciler: 2, ledger: 2, payout: 2, settlement: 1, rounding: 1, cents: 1,
      retry: 2, backoff: 1, worker: 2, webhook: 1, replay: 1, dunning: 1, production: 4,
      deploy: 3, staging: 2, release: 2, schema: 1, migration: 1, refund: 1, 'bill-412': 1,
    },
    size: 30000,
  },
  // The 0.6.7 case: `production` is on most of the vault, so the question only separates on
  // the two rare terms beside it.
  'topics/reconciler-double-count': {
    terms: { reconciler: 7, ledger: 4, production: 2, invoice: 1 },
    size: 3200,
  },
  // A page whose own text never writes its name — the 0.6.5 defect. `version` and `train`
  // appear nowhere in `terms`, so it can only be found through the page list.
  'topics/version-train': {
    terms: { release: 3, staging: 2, deploy: 2 },
    size: 1800,
  },
  'topics/payout-settlement': {
    terms: { payout: 6, settlement: 5, ledger: 1, production: 1 },
    size: 2800,
  },
  'decisions/2026-08-14-invoice-worker-retries-with-backoff': {
    terms: { retry: 6, backoff: 5, worker: 4, invoice: 2, production: 1 },
    size: 3000,
  },
  'topics/webhook-replay': {
    terms: { webhook: 5, replay: 4, retry: 1, production: 1 },
    size: 2400,
  },
  // The disambiguation pair: both pages are about replaying something, and the question
  // "invoice replay" has to pick the one whose subject is invoices.
  'topics/manual-invoice-replay': {
    terms: { invoice: 6, replay: 5, worker: 2, ledger: 1 },
    size: 2700,
  },
  'topics/dunning-schedule': {
    terms: { dunning: 6, invoice: 2, refund: 1 },
    size: 2200,
  },
  // A page that merely mentions a subject in passing, to stand against the page about it.
  'people/platform-team': {
    terms: { reconciler: 1, deploy: 1, production: 1 },
    size: 1500,
  },
  'topics/release-process': {
    terms: { release: 7, deploy: 6, staging: 4, production: 3 },
    size: 3400,
  },
  'topics/schema-migrations': {
    terms: { schema: 6, migration: 5, deploy: 1, production: 1 },
    size: 2900,
  },
}

// Filler, so that document frequency and the average page length are those of a vault rather
// than of a dozen pages. Generated from the index alone, so the corpus is fixed by this file:
// every page carries `production`, which is what makes `production` unable to separate
// anything, and a rotating mid-frequency term so the distribution is not flat.
const FILLER_TERMS = ['deploy', 'invoice', 'ledger', 'release', 'worker', 'schema', 'refund']
const filler = (): Record<string, Page> => {
  const out: Record<string, Page> = {}
  for (let i = 1; i <= 28; i++) {
    const slug = `topics/filler-${String(i).padStart(2, '0')}`
    out[slug] = {
      terms: {
        production: 1 + (i % 3),
        [FILLER_TERMS[i % FILLER_TERMS.length] as string]: 1 + (i % 2),
      },
      size: 2000 + (i % 7) * 400,
    }
  }
  return out
}

export const CORPUS: Record<string, Page> = { ...NAMED, ...filler() }

export type Question = {
  query: string
  // The page the question is about. One page, so a rank is unambiguous.
  gold: string
  // What ranking decision this question puts under load. A question with no trap measures
  // nothing a smaller test would not.
  trap: string
  // The rank the gold page currently gets, 1-based, or null when it does not come back at
  // all. This is the frozen part: the harness fails when a rank gets worse, and tells you to
  // update the baseline when one gets better. Every value here was read off a run, never
  // predicted — a guessed baseline asserts the author's belief instead of the behaviour, and
  // the first two written here were both wrong.
  baseline: number | null
}

export const QUESTIONS: Question[] = [
  {
    query: 'BILL-412 rounding',
    gold: 'topics/invoice-rounding',
    trap: 'a rare identifier beside a topic term — the easiest case, and the one that must never regress',
    baseline: 1,
  },
  {
    query: 'production reconciler ledger',
    gold: 'topics/reconciler-double-count',
    trap: 'one term is on every page in the corpus, so only the two rare terms separate anything (the 0.6.7 defect)',
    baseline: 1,
  },
  {
    query: 'version train',
    gold: 'topics/version-train',
    trap: "the page's text never writes its own name, so it exists only in the page list (the 0.6.5 defect)",
    baseline: 1,
  },
  {
    query: 'invoice cents',
    gold: 'topics/invoice-rounding',
    trap: 'a page ten times longer carries both terms too, so the length divisor decides it',
    baseline: 1,
  },
  {
    query: 'invoice replay',
    gold: 'topics/manual-invoice-replay',
    trap: 'two pages are about replaying something; only the term balance says which subject',
    baseline: 1,
  },
  {
    query: 'retry backoff worker',
    gold: 'decisions/2026-08-14-invoice-worker-retries-with-backoff',
    trap: 'the gold page is in decisions/, which sorts before topics/ — a tie here would hide a scoring bug',
    baseline: 1,
  },
  {
    query: 'payout settlement',
    gold: 'topics/payout-settlement',
    trap: 'both terms are rare and on one page, which is the case every ranking gets right',
    baseline: 1,
  },
  {
    query: 'dunning',
    gold: 'topics/dunning-schedule',
    trap: 'a single rare term, where the page name and the text agree',
    baseline: 1,
  },
  {
    query: 'webhook replay',
    gold: 'topics/webhook-replay',
    trap: 'a competing page says `replay` more often, so the rarer term has to carry it',
    baseline: 1,
  },
  {
    query: 'schema migration staging',
    gold: 'topics/schema-migrations',
    trap: "the page's name is plural and the query is singular, so the name match is a substring one",
    baseline: 1,
  },
  {
    query: 'reconciler',
    gold: 'topics/reconciler-double-count',
    trap: 'a page mentioning the subject once stands against the page about it',
    baseline: 1,
  },
  // The questions below are expected to do badly. They are here so that the fixture cannot be
  // passed by a ranking that only handles the winnable cases, and so that a change which
  // happens to fix one is reported rather than silently absorbed.
  {
    query: 'production',
    gold: 'topics/reconciler-double-count',
    trap: 'EXPECTED MISS: one term, on all 40 pages. Nothing can separate this, and a ranking that puts a particular page first here is fitting noise',
    baseline: null,
  },
  {
    query: 'deploy production staging',
    gold: 'topics/version-train',
    trap: 'every term is common, so a short page carrying two of them places on length alone — the one question here that is neither a win nor a miss, and so the one whose movement is informative',
    baseline: 2,
  },
  // Vocabulary mismatch: the gold page is the right answer and shares no literal with the
  // question. This is the class that fails on a real vault — a question asked as a sentence,
  // in a plural or a paraphrase the page never uses — and nothing above covers it, because
  // every question above hands the ranking a word the page actually carries. These two are
  // the before-and-after for a second retrieval signal: a bigram fallback for a query whose
  // terms return nothing at all, and a page's own `aliases:` line.
  // Both questions below avoid any word that is a substring of a page's name, which is not a
  // free choice: a query term is kept at two characters and matched against the name as a
  // substring, so `why do invoices get paid twice` returns the double-counting page first —
  // `do` is inside `double-count`. That is the right page for the wrong reason, and a fixture
  // entry resting on it would turn the eventual stopword filter into a reported regression.
  // The artifact is left alone here because it is a separate behaviour change needing its own
  // measurement, not because it is harmless.
  {
    query: 'invoices counted more than once',
    gold: 'topics/reconciler-double-count',
    trap: 'EXPECTED MISS: a sentence whose every word is absent from the page and its name — `invoices` does not match `invoice`, so the term set returns no candidate at all',
    baseline: null,
  },
  {
    query: 'shipping changes safely',
    gold: 'topics/release-process',
    trap: "EXPECTED MISS: a paraphrase of the page's subject sharing no word with it, which is what a reader asks before they know the vault's vocabulary",
    baseline: null,
  },
]
