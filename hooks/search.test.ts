import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { TestBody } from 'claude-code/testing'
import { TOOL } from './register'

// What is left to test here is the wiring: the registered tool runs scripts/search.sh against
// the session's directory and hands back what it said. The ranking itself, and every assertion
// about what outranks what, lives in scripts/test-search-ranking.sh, which runs the real script
// over a generated vault. Those assertions used to be here, against a mock of grep, and the
// mock was wrong in two ways that mattered — `grep -c` counts matching lines rather than
// occurrences, and a term matches as a substring — so they were passing on behaviour the
// script does not have.
const wired = (
  on: On,
  out: { exitCode?: number; stdout?: string } = {},
): { argv: string[][] } => {
  const argv: string[][] = []
  on('session.cwd', () => ({ value: '/home/t/Repos/acme-billing' }))
  on('process.run', ($, e) => {
    argv.push([...e.argv])
    return {
      value: {
        exitCode: out.exitCode ?? 0,
        stdout: out.stdout ?? 'The 1 best of 1 pages that mention any of these terms, highest first.\n',
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    }
  })
  return { argv }
}

const ask = ($: Parameters<TestBody>[0], query: string) =>
  ($.tool.call as (i: { tool: string; input: unknown }) => Promise<{ result?: unknown }>)({
    tool: TOOL,
    input: { query },
  })

test("the query and the session's directory are handed to the search script", async ($, on) => {
  const { argv } = wired(on)

  await ask($, 'BILL-412 rounding')

  const call = argv.find(a => a[0]?.endsWith('scripts/search.sh'))
  expect(call).toBeDefined()
  // The whole query travels as one argument after `--`, so a term that looks like an option
  // cannot be read as one.
  expect(call?.slice(1)).toEqual(['--cwd', '/home/t/Repos/acme-billing', '--', 'BILL-412 rounding'])
})

test("the script's answer is returned as it was written", async ($, on) => {
  // The script writes for the model — which pages, in what order, what each one leads with —
  // and nothing here reformats it, so a change to that prose needs no change in this file.
  wired(on, { stdout: '## [[topics/invoice-rounding]]  (2/2 terms)\nA lead.\n\n' })

  const { result } = await ask($, 'BILL-412 rounding')

  expect(result).toBe('## [[topics/invoice-rounding]]  (2/2 terms)\nA lead.')
})

test('a vault-less directory and an unmatched query are the script\'s own answers, not failures', async ($, on) => {
  // Both exit 0 with prose, because neither is an error the model should be told to work
  // around; translating them here would mean two places deciding what they say.
  wired(on, { stdout: 'No Brain vault covers this directory, so there is nothing to search.\n' })

  const { result } = await ask($, 'reconciler')

  expect(result).toBe('No Brain vault covers this directory, so there is nothing to search.')
})

test('a script that fails is reported as one, with somewhere else to go', async ($, on) => {
  wired(on, { exitCode: 2, stdout: '' })

  const { result } = await ask($, 'reconciler')

  expect(result).toContain('did not run')
  expect(result).toContain('/brain:query')
})

test('a script that exits clean with nothing to say is treated as a failure', async ($, on) => {
  // Empty output would reach the model as a tool that answered with silence, which reads as
  // "the vault holds nothing about this" — the one wrong conclusion to hand it.
  wired(on, { exitCode: 0, stdout: '   \n' })

  const { result } = await ask($, 'reconciler')

  expect(result).toContain('did not run')
})
