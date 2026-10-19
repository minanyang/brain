import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { TestBody } from 'claude-code/testing'
import { TOOL } from './register'
import { CORPUS, QUESTIONS, VAULT } from './ranking-fixture'

// The corpus is served through the same three calls the tool makes against a real vault — the
// page list, one count per term, and the page sizes — so what is measured is the ranking and
// not a reimplementation of it.
const serve = (on: On): void => {
  const paths = Object.keys(CORPUS).map(slug => `${VAULT}/${slug}.md`)
  const slugOf = (p: string) => p.slice(VAULT.length + 1).replace(/\.md$/, '')

  on('session.cwd', () => ({ value: '/home/t/Repos/acme-billing' }))
  on('fs.read', () => ({
    // Only the lead is printed, and nothing in the ranking reads it; a constant keeps the
    // fixture about the order.
    value: '---\ntitle: A page\ntype: topic\n---\n\nA fabricated page in the acme-billing vault.\n',
  }))
  on('process.run', ($, e) => {
    const run = (exitCode: number, stdout: string) => ({
      value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (e.argv[0]?.endsWith('resolve-vault.sh')) return run(0, `acme-billing\t${VAULT}\n`)
    if (e.argv[0] === 'find') return run(0, paths.join('\n'))
    if (e.argv[0] === 'wc') {
      return run(0, paths.map(p => `${CORPUS[slugOf(p)]?.size ?? 1} ${p}`).join('\n'))
    }
    // The count call the ranking is built on: `grep -ric` gives one `path:count` per page.
    if (e.argv.includes('-ric')) {
      const term = (e.argv[e.argv.indexOf('-e') + 1] ?? '').toLowerCase()
      const hits = paths
        .map(p => [p, CORPUS[slugOf(p)]?.terms[term] ?? 0] as const)
        .filter(([, n]) => n > 0)
      return run(hits.length === 0 ? 1 : 0, hits.map(([p, n]) => `${p}:${n}`).join('\n'))
    }
    // The excerpt call, made once per page that is about to be shown.
    if (e.argv.includes('-in')) return run(0, '12:  a fabricated line mentioning the term')
    return run(1, '')
  })
}

const ask = ($: Parameters<TestBody>[0], query: string) =>
  ($.tool.call as (i: { tool: string; input: unknown }) => Promise<{ result?: unknown }>)({
    tool: TOOL,
    input: { query },
  })

// The result lists the pages it returns as `## [[dir/page]]  (n/m terms)`, best first, so the
// gold page's rank is where its heading falls in that sequence.
const rankOf = (text: string, gold: string): number | null => {
  const order = [...text.matchAll(/^## \[\[(.+?)\]\]/gm)].map(m => m[1])
  const i = order.indexOf(gold)
  return i === -1 ? null : i + 1
}

const show = (r: number | null) => (r === null ? 'absent' : `#${r}`)

test('every fixture question returns its gold page no lower than the frozen baseline', async ($, on) => {
  serve(on)

  const rows: string[] = []
  const worse: string[] = []
  const better: string[] = []
  let found = 0
  let reciprocal = 0

  for (const q of QUESTIONS) {
    const text = String((await ask($, q.query)).result)
    const got = rankOf(text, q.gold)
    if (got !== null) {
      found++
      reciprocal += 1 / got
    }
    // A null baseline means the page did not come back at all, so any rank is an improvement;
    // a numbered baseline is beaten by a smaller number.
    if (q.baseline === null ? got !== null : got === null || got > q.baseline) {
      worse.push(`${q.query} → ${q.gold}: baseline ${show(q.baseline)}, got ${show(got)}`)
    } else if (q.baseline !== null && got !== null && got < q.baseline) {
      better.push(`${q.query} → ${q.gold}: baseline ${show(q.baseline)}, got ${show(got)}`)
    }
    rows.push(`  ${show(got).padEnd(7)} (was ${show(q.baseline).padEnd(6)}) ${q.query}`)
  }

  const recall = found / QUESTIONS.length
  const mrr = reciprocal / QUESTIONS.length
  // Printed on every run, per question, because an aggregate hides the mechanism: a documented
  // case elsewhere in this field moved +0.070 overall while one category inside it moved +0.239.
  console.log(
    [
      `ranking fixture: ${CORPUS ? Object.keys(CORPUS).length : 0} pages, ${QUESTIONS.length} questions`,
      ...rows,
      `  recall@8 ${recall.toFixed(3)}   MRR ${mrr.toFixed(3)}`,
    ].join('\n'),
  )

  if (better.length > 0) {
    console.log(
      ['ranking improved — update the baselines in ranking-fixture.ts:', ...better.map(b => `  ${b}`)].join('\n'),
    )
  }
  // The baselines are the assertion. An aggregate floor would let one question collapse while
  // another happened to improve, which is the trade this fixture exists to make visible.
  expect(worse).toEqual([])
})

test('the fixture keeps questions the ranking is expected to fail', async ($, on) => {
  serve(on)

  // A fixture of winnable questions is a floor that never trips: it would pass a ranking that
  // handles only the cases already handled. At least one question must be a known miss, and
  // the previous test is what reports it the day one starts passing.
  const misses = QUESTIONS.filter(q => q.baseline === null)

  expect(misses.length).toBeGreaterThan(0)
  for (const q of misses) expect(q.trap).toContain('EXPECTED MISS')
})
