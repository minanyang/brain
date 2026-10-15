import { expect, mock, test } from 'claude-code/testing'
import type { On, SessionMessage } from 'claude-code'
import type { TestBody } from 'claude-code/testing'

const CLAIM =
  'The acme-billing reconciler runs nightly at 02:00 and matches invoices to payments in one pass.'

type Written = { path: string; text: string }

// A vault that routes, a classifier that answers, a secret gate that redacts, and a
// transcript whose last message is the agent's. Every call the hook makes is counted, so a
// test can say the gate kept the model call from happening at all.
const session = (
  on: On,
  options: {
    messages?: SessionMessage[]
    label?: 'correction' | 'instruction' | 'other'
    routed?: string | null
    failWrite?: true
  } = {},
): { written: Written[]; classified: string[] } => {
  const written: Written[] = []
  const classified: string[] = []
  const messages = options.messages ?? [
    { role: 'user', text: 'when does the reconciler run?', toolUses: [] },
    { role: 'assistant', text: CLAIM, toolUses: [] },
  ]
  mock.clock(on, { now: Date.parse('2026-10-15T09:41:07Z') })
  // Nothing sits beneath the plugins in a test, so the engine's own two ends are the test's.
  on('prompt.submit', ($, e) => ({ text: e.text }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/home/t/Repos/acme-billing' }))
  on('session.id', () => ({ value: 'fabricated-session-001' }))
  on('session.messages', () => ({ value: messages }))
  on('model.classify', ($, e) => {
    classified.push(e.text)
    const chosen = e.labels.find(l => l.startsWith(`${options.label ?? 'correction'}:`))
    return { value: chosen }
  })
  on('fs.write', ($, e) => {
    if (options.failWrite) throw new Error('read-only vault')
    written.push({ path: e.path, text: e.text })
    return { value: undefined }
  })
  on('process.run', ($, e) => {
    const run = (exitCode: number, stdout: string) => ({
      value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    })
    if (e.argv[0]?.endsWith('resolve-vault.sh')) {
      const routed = options.routed === undefined ? '/home/t/acme-billing' : options.routed
      return routed === null ? run(1, '') : run(0, `acme-billing\t${routed}\n`)
    }
    if (e.argv[0]?.endsWith('secret-gate.sh')) {
      // The real gate replaces a credential with [redacted]; this stands in for it.
      return run(0, `${(e.init?.stdin ?? '').replace(/sk-[A-Za-z0-9_-]{20,}/g, '[redacted]')}\n`)
    }
    return run(0, '')
  })
  return { written, classified }
}

const submit = (
  $: Parameters<TestBody>[0],
  text: string,
  extra: { turnId?: string; origin?: { kind: 'composer' } | { kind: 'sdk' } } = {},
) => $.prompt.submit({ text, wait: false, origin: { kind: 'composer' }, ...extra })

test('a correction of the last claim is written to .state as a candidate, verbatim', async ($, on) => {
  const { written } = session(on)

  const result = await submit($, '不對，reconciler 是每小時跑一次。')

  expect(written).toHaveLength(1)
  const [file] = written
  expect(file?.path).toBe('/home/t/acme-billing/.state/corrections/2026-10-15-094107-fabricat.md')
  expect(file?.text).toContain('不對，reconciler 是每小時跑一次。')
  expect(file?.text).toContain(CLAIM)
  expect(file?.text).toContain('kind: correction-candidate')
  expect(file?.text).toContain('date: 2026-10-15')
  // The prompt still enters: the hook records, it does not gate the conversation.
  expect(result.text).toBe('不對，reconciler 是每小時跑一次。')
})

test('the candidate says it decides nothing, names the only write path, and points at restated.sh', async ($, on) => {
  const { written } = session(on)

  await submit($, 'that is wrong, it runs hourly')

  const text = written[0]?.text ?? ''
  expect(text).toContain('finish.sh')
  expect(text).toContain('/brain:ingest')
  expect(text).toContain('restated.sh')
  expect(text).toContain('no page was edited and no conflict was resolved')
})

test('the classifier is shown the claim as well as the reply, so a bare contradiction is judgeable', async ($, on) => {
  const { classified } = session(on)

  await submit($, 'reconciler 是每小時跑一次')

  expect(classified[0]).toContain(CLAIM)
  expect(classified[0]).toContain('reconciler 是每小時跑一次')
})

test('a change of mind about what to do next is not a correction', async ($, on) => {
  const { written } = session(on, { label: 'instruction' })

  await submit($, 'no, do the migration first')

  expect(written).toHaveLength(0)
})

test('a prompt past the length cap never reaches the classifier', async ($, on) => {
  const { written, classified } = session(on)

  await submit($, `that is wrong. ${'the reconciler matches on payment id, and '.repeat(10)}`)

  expect(classified).toHaveLength(0)
  expect(written).toHaveLength(0)
})

test('nothing is classified when the previous turn asked a question instead of claiming', async ($, on) => {
  const { classified } = session(on, {
    messages: [{ role: 'assistant', text: 'Which of the two reconciler runs do you mean, the nightly one?', toolUses: [] }],
  })

  await submit($, 'that is wrong')

  expect(classified).toHaveLength(0)
})

test('nothing is classified for a prompt typed over a running turn', async ($, on) => {
  const { classified } = session(on)

  await submit($, 'that is wrong', { turnId: 'turn-001' })

  expect(classified).toHaveLength(0)
})

test('a prompt the headless host submitted is never quoted as the user\'s words', async ($, on) => {
  const { written, classified } = session(on)

  await submit($, 'that is wrong, it runs hourly', { origin: { kind: 'sdk' } })

  expect(classified).toHaveLength(0)
  expect(written).toHaveLength(0)
})

test('a credential in the prompt reaches neither the classifier nor the vault', async ($, on) => {
  const { written, classified } = session(on)

  await submit($, 'wrong — the token is sk-abcdefghijklmnopqrstuvwxyz01')

  expect(classified[0]).not.toContain('sk-abcdefghij')
  expect(classified[0]).toContain('[redacted]')
  expect(written[0]?.text).not.toContain('sk-abcdefghij')
  expect(written[0]?.text).toContain('[redacted]')
})

test('a directory no vault covers costs no model call and writes nothing', async ($, on) => {
  const { written, classified } = session(on, { routed: null })

  await submit($, 'that is wrong, it runs hourly')

  expect(classified).toHaveLength(0)
  expect(written).toHaveLength(0)
})

test('a prompt still enters when the write fails', async ($, on) => {
  session(on, { failWrite: true })

  const result = await submit($, 'that is wrong, it runs hourly')

  expect(result.text).toBe('that is wrong, it runs hourly')
})
