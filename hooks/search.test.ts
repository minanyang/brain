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
    const term = e.argv[e.argv.indexOf('-e') + 1] ?? ''
    const files: string[] = matches[term] ?? []
    return run(
      files.length === 0 ? 1 : 0,
      // `grep -n` output when the call asks for matching lines rather than names.
      e.argv.includes('-n')
        ? files.map(f => `12:  a line of ${f} mentioning ${term}`).join('\n')
        : files.join('\n'),
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
