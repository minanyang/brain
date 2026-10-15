import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { TestBody } from 'claude-code/testing'
import { TOOL } from './register'

const PAGE = `---
title: Invoice rounding
type: topic
---

BILL-412 moved every invoice total to integer cents.

## Phases
- Phase 2 landed on main.
`

// resolve-vault.sh is the only thing that decides which vault a directory belongs to, so a
// test says what it answered rather than what a config file holds. `searched` collects the
// directories grep was pointed at, which is how the routed vault is told from any other.
const vault = (
  on: On,
  matches: Record<string, string[]>,
  routed: string | null = '/home/t/acme-billing',
  pages: string[] = [],
  // How often each page says each term, and how long each page is: what BM25 ranks on. A term
  // left out of `counts` is said once by every page `matches` lists for it.
  extra: { counts?: Record<string, Record<string, number>>; sizes?: Record<string, number> } = {},
): { searched: string[] } => {
  const searched: string[] = []
  on('session.cwd', () => ({ value: '/home/t/Repos/acme-billing' }))
  on('fs.read', () => ({ value: PAGE }))
  on('process.run', ($, e) => {
    const run = (exitCode: number, stdout: string) => ({
      value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (e.argv[0]?.endsWith('resolve-vault.sh')) {
      return routed === null ? run(1, '') : run(0, `acme-billing\t${routed}\n`)
    }
    searched.push(...e.argv.filter(a => a.startsWith('/')))
    // The page list, which is what makes a page's own name searchable.
    if (e.argv[0] === 'find') return run(pages.length === 0 ? 1 : 0, pages.join('\n'))
    if (e.argv[0] === 'wc') {
      const paths = e.argv.filter(a => a.startsWith('/'))
      return run(0, paths.map(f => `${extra.sizes?.[f] ?? 1000} ${f}`).join('\n'))
    }
    const term = e.argv[e.argv.indexOf('-e') + 1] ?? ''
    const counts = extra.counts?.[term]
    const files: string[] = counts !== undefined ? Object.keys(counts) : (matches[term] ?? [])
    return run(
      files.length === 0 ? 1 : 0,
      // `grep -n` output when the call asks for matching lines rather than names, `grep -c`
      // output — one `path:count` per page — when it asks how often each page says the term.
      e.argv.includes('-n')
        ? files.map(f => `12:  a line of ${f} mentioning ${term}`).join('\n')
        : files.map(f => `${f}:${counts?.[f] ?? 1}`).join('\n'),
    )
  })
  return { searched }
}

// The tool is registered at run time, so its name is outside the engine's generated
// union of callable tool names; the call itself is ordinary.
const ask = ($: Parameters<TestBody>[0], query: string) =>
  ($.tool.call as (i: { tool: string; input: unknown }) => Promise<{ result?: unknown }>)({
    tool: TOOL,
    input: { query },
  })

test('a query too short to be a term is told so rather than searched', async ($, on) => {
  vault(on, {})

  const { result } = await ask($, 'a')

  expect(result).toContain('two characters or more')
})

test('nothing matching is said plainly, naming what was looked for', async ($, on) => {
  vault(on, {})

  const { result } = await ask($, 'kafka')

  expect(result).toContain('"kafka"')
})

test('pages matching more of the terms rank first, in citable form', async ($, on) => {
  vault(on, {
    'BILL-412': ['/home/t/acme-billing/topics/invoice-rounding.md', '/home/t/acme-billing/projects/acme-billing.md'],
    rounding: ['/home/t/acme-billing/topics/invoice-rounding.md'],
  })

  const { result } = await ask($, 'BILL-412 rounding')
  const text = String(result)

  expect(text).toContain('[[topics/invoice-rounding]]  (2/2 terms)')
  expect(text).toContain('[[projects/acme-billing]]  (1/2 terms)')
  expect(text.indexOf('invoice-rounding')).toBeLessThan(text.indexOf('projects/acme-billing'))
  // The lead, not the frontmatter, is what says whether the page is worth opening.
  expect(text).toContain('BILL-412 moved every invoice total to integer cents.')
  expect(text).not.toContain('type: topic')
})

test('the vault searched is the one the cwd routes to, not the first in the config', async ($, on) => {
  const { searched } = vault(on, {}, '/home/t/vaults/second')

  await ask($, 'reconciler')

  expect(searched).toContain('/home/t/vaults/second/projects')
  expect(searched.some(d => d.startsWith('/home/t/acme-billing'))).toBe(false)
})

test('a directory no vault covers is told so rather than searched', async ($, on) => {
  vault(on, {}, null)

  const { result } = await ask($, 'reconciler')

  expect(result).toContain('No Brain vault covers this directory')
})

test("a page is found by its own name, which its text does not repeat", async ($, on) => {
  // The defect this covers: nothing in `topics/version-train.md` writes the words "version
  // train", so a grep over contents returned only the pages linking to it.
  vault(on, {}, '/home/t/acme-billing', ['/home/t/acme-billing/topics/invoice-rounding.md'])

  const { result } = await ask($, 'invoice rounding')
  const text = String(result)

  expect(text).toContain('[[topics/invoice-rounding]]  (2/2 terms)')
  expect(text).toContain("matched on the page's name")
})

test('a term in both the name and the text counts once, not twice', async ($, on) => {
  vault(
    on,
    { rounding: ['/home/t/acme-billing/topics/invoice-rounding.md'] },
    '/home/t/acme-billing',
    ['/home/t/acme-billing/topics/invoice-rounding.md'],
  )

  const { result } = await ask($, 'rounding')
  const text = String(result)

  expect(text).toContain('(1/1 terms)')
  // The text matched, so the page is quoted rather than labelled as a name-only hit.
  expect(text).not.toContain("matched on the page's name")
})

test('a page that keeps saying the term outranks one that mentions it in passing', async ($, on) => {
  const page = (n: string) => `/home/t/acme-billing/topics/${n}.md`
  vault(on, {}, '/home/t/acme-billing', [page('alpha'), page('zulu')], {
    counts: { rounding: { [page('alpha')]: 1, [page('zulu')]: 9 } },
    sizes: { [page('alpha')]: 4000, [page('zulu')]: 4000 },
  })

  const text = String((await ask($, 'rounding')).result)

  expect(text.indexOf('topics/zulu')).toBeLessThan(text.indexOf('topics/alpha'))
})

test('a term nearly every page carries does not decide the order', async ($, on) => {
  // The defect: ranking by terms matched put 38 of a 202-page vault on one score, because
  // `production` was on 138 of them, and the tie fell to the path — which sorts `topics/`
  // last, so the directory holding most of the vault could not place at all.
  const page = (n: string) => `/home/t/acme-billing/topics/${n}.md`
  const pages = [page('alpha'), page('beta'), page('zulu')]
  vault(on, {}, '/home/t/acme-billing', pages, {
    counts: {
      production: { [page('alpha')]: 1, [page('beta')]: 1, [page('zulu')]: 1 },
      ingress: { [page('alpha')]: 1, [page('beta')]: 1, [page('zulu')]: 7 },
    },
    sizes: Object.fromEntries(pages.map(f => [f, 4000])),
  })

  const text = String((await ask($, 'production ingress')).result)

  expect(text).toContain('[[topics/zulu]]  (2/2 terms)')
  expect(text.indexOf('topics/zulu')).toBeLessThan(text.indexOf('topics/alpha'))
})

test('a long page does not outrank a short one on bulk alone', async ($, on) => {
  const page = (n: string) => `/home/t/acme-billing/topics/${n}.md`
  vault(on, {}, '/home/t/acme-billing', [page('alpha'), page('zulu')], {
    counts: { rounding: { [page('alpha')]: 4, [page('zulu')]: 4 } },
    sizes: { [page('alpha')]: 40000, [page('zulu')]: 2000 },
  })

  const text = String((await ask($, 'rounding')).result)

  expect(text.indexOf('topics/zulu')).toBeLessThan(text.indexOf('topics/alpha'))
})
