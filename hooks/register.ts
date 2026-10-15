import type { EngineInterface, Register, SessionMessage } from 'claude-code'

// Two defences, one module: a tool that makes the vault reachable (read side), and a hook
// that catches a correction where it happens (write side).

// ---------------------------------------------------------------------------------------
// Resolving the vault
// ---------------------------------------------------------------------------------------

// The prototype read ~/.brain/config.json and took vaults[0]. That is wrong on any machine
// with more than one vault, and reimplementing the routing here would be a second copy of
// lib.sh to keep in step, so both hooks below shell out to the plugin's own
// resolve-vault.sh: it honours BRAIN_CONFIG, prefers the vault the cwd is inside, and
// otherwise walks the vaults' include globs in registration order, which is the precedence
// /brain:init relies on when it inserts a new vault first.
const resolveVault = async ($: EngineInterface): Promise<string | undefined> => {
  const cwd = await $.session.cwd()
  const { exitCode, stdout } = await $.process.run(
    [`${$.plugin.root}/scripts/resolve-vault.sh`, '--cwd', cwd],
    { timeoutMs: 15000 },
  )
  // Exit 1 is "no vault for this directory", which is the ordinary case outside a routed
  // tree and not an error worth reporting to the model.
  if (exitCode !== 0) return undefined
  const path = stdout.split('\n')[0]?.split('\t')[1]
  return path !== undefined && path !== '' ? path : undefined
}

// ---------------------------------------------------------------------------------------
// Failure mode 1: the vault is not read, because a skill has to be triggered
// ---------------------------------------------------------------------------------------

// The session-start list carries at most 20 of the vault's pages. The rest were reachable
// only through /brain:query, and across 40 real interactive sessions between 2026-10-08 and
// 2026-10-15 that skill was invoked in 0 of them: 37 of the 40 received the injected brief, a
// vault page was opened in 4 of those 37, and in all four the agent reached for `sed -n` or
// `cat` on a page path instead of the skill. A skill has to be triggered; a registered tool is
// in the tool list every turn. That is an observation, not a hope, and it is the whole
// argument for this tool.
const DESCRIPTION = `Search every page of the user's Brain vault — their private wiki of
decisions, project state, people and past investigations — and get back the matching pages
with their opening summary and the lines that matched.

Use this whenever a question turns on something the repository and the live systems cannot
settle: why a thing was decided, what was tried and abandoned, who owns something, what a
ticket's state was, or what happened between two releases. The session-start page list is a
small excerpt of the vault, so a subject missing from it is not missing from the vault.

Answering such a question from general knowledge instead produces a confident wrong answer,
which is the costlier failure: the vault exists because the user corrected those once already.
Cite what you use as [[directory/page]].`

const WIKI_DIRS = ['me', 'people', 'projects', 'decisions', 'topics']
const MAX_PAGES = 8

// The lead is the page's first paragraph after the frontmatter: what index.md quotes
// and the one line that says whether this page is worth opening.
const lead = (text: string): string => {
  const body = text.replace(/^---\n[\s\S]*?\n---\n/, '')
  return (body.split(/\n\s*\n/).find(p => p.trim() !== '') ?? '').replace(/\s+/g, ' ').trim()
}

const search = async ($: EngineInterface, query: string): Promise<string> => {
  const vault = await resolveVault($)
  if (vault === undefined) return 'No Brain vault covers this directory, so there is nothing to search.'

  const terms = query.split(/\s+/).filter(t => t.length >= 2).slice(0, 8)
  const first = terms[0]
  if (first === undefined) return 'Give at least one search term of two characters or more.'

  const dirs = WIKI_DIRS.map(d => `${vault}/${d}`)

  // A page's own name is nowhere in its text, so grep over contents alone answers the most
  // obvious query with every page but the right one: searching `version-train` returned the
  // page that links to [[topics/version-train]] and not the page itself. The path is part of
  // what a reader means by a page's name, so it is searched too.
  const { stdout: listed } = await $.process.run(
    ['find', ...dirs, '-type', 'f', '-name', '*.md'],
    { timeoutMs: 15000 },
  )
  const names = new Map<string, string>()
  for (const file of listed.split('\n').filter(Boolean)) {
    const slug = file.slice(vault.length + 1).replace(/\.md$/, '').toLowerCase()
    // `topics/cross-midnight-business-hours` should answer "cross midnight" as well as the
    // hyphenated form, so both spellings are matched against.
    names.set(file, `${slug} ${slug.replace(/[-/]/g, ' ')}`)
  }

  // One grep per term, counting how often each page says it. Ranking by the number of terms a
  // page mentions at all cannot separate an ordinary question: measured against a 202-page
  // vault, a three-word question about who reaches one production database put 38 pages on
  // the identical score and the same question asked in a sentence put 25 there, because a
  // word like `production` was on 138 of them. The tie then fell through to the path, which
  // sorts `topics/` after every other directory, so the 137 pages holding most of that vault
  // could not place in the top 8 at all and the page that answered was never returned.
  const tf = new Map<string, Map<string, number>>()
  const byName = new Set<string>()
  for (const term of terms) {
    const { stdout } = await $.process.run(
      ['grep', '-ric', '--include=*.md', '-e', term, ...dirs],
      { timeoutMs: 15000 },
    )
    const counted = new Map<string, number>()
    for (const line of stdout.split('\n')) {
      const cut = line.lastIndexOf(':')
      if (cut < 1) continue
      const n = Number(line.slice(cut + 1))
      if (Number.isFinite(n) && n > 0) counted.set(line.slice(0, cut), n)
    }
    const t = term.toLowerCase()
    for (const [file, name] of names) {
      if (!name.includes(t)) continue
      if (!counted.has(file)) byName.add(file)
      // A term in the page's own name is what the page is *about*, so it counts as a mention
      // the body would have had to repeat to earn.
      counted.set(file, (counted.get(file) ?? 0) + 2)
    }
    for (const [file, n] of counted) {
      const row = tf.get(file) ?? new Map<string, number>()
      row.set(term, n)
      tf.set(file, row)
    }
  }
  if (tf.size === 0) return `No page mentions ${terms.map(t => `"${t}"`).join(' or ')}.`

  // Page length, so that repetition on a short page about the subject outranks one mention
  // apiece on a long page that touches everything.
  const { stdout: sized } = await $.process.run(['wc', '-c', ...names.keys()], { timeoutMs: 15000 })
  const length = new Map<string, number>()
  for (const line of sized.split('\n')) {
    const m = /^\s*(\d+)\s+(\S.*)$/.exec(line)
    if (m?.[2] !== undefined && m[2] !== 'total') length.set(m[2], Math.max(Number(m[1]), 1))
  }
  const sizes = [...length.values()]
  const avg = sizes.length > 0 ? sizes.reduce((a, b) => a + b, 0) / sizes.length : 1
  const total = Math.max(names.size, tf.size, 1)
  const df = new Map<string, number>()
  for (const row of tf.values()) for (const term of row.keys()) df.set(term, (df.get(term) ?? 0) + 1)

  // BM25, with its usual constants: a term on most pages separates nothing, a repeated term
  // counts with diminishing return, and the length divisor is what keeps the long pages honest.
  const K1 = 1.2
  const B = 0.75
  const score = new Map<string, number>()
  for (const [file, row] of tf) {
    let s = 0
    for (const [term, n] of row) {
      const d = df.get(term) ?? 1
      const idf = Math.log(1 + (total - d + 0.5) / (d + 0.5))
      s += (idf * n * (K1 + 1)) / (n + K1 * (1 - B + (B * (length.get(file) ?? avg)) / avg))
    }
    score.set(file, s)
  }

  // Where two pages score the same, the page *called* X answers "X" better than a page that
  // merely links to it, so a name hit breaks the tie before the path does.
  const rank = (f: string) => (byName.has(f) ? 1 : 0)
  const ranked = [...tf.entries()]
    .map(([file, row]) => [file, row.size] as const)
    .sort(
      (a, b) =>
        (score.get(b[0]) ?? 0) - (score.get(a[0]) ?? 0) ||
        rank(b[0]) - rank(a[0]) ||
        a[0].localeCompare(b[0]),
    )
  const out: string[] = []
  for (const [file, matched] of ranked.slice(0, MAX_PAGES)) {
    const page = file.slice(vault.length + 1).replace(/\.md$/, '')
    const text = await $.fs.read(file)
    const { stdout: lines } = await $.process.run(
      ['grep', '-in', '-m', '3', '-e', first, file],
      { timeoutMs: 10000 },
    )
    // A page found by its name alone has no line to quote; saying so is what stops the
    // empty excerpt reading as a page whose body has nothing to do with the question.
    const excerpt = lines.split('\n').filter(Boolean).map(l => `  ${l.slice(0, 300)}`).join('\n')
      || (byName.has(file) ? "  (matched on the page's name; its text does not repeat it)" : '')
    out.push(`## [[${page}]]  (${matched}/${terms.length} terms)\n${lead(text)}\n${excerpt}`)
  }
  const more = ranked.length > MAX_PAGES ? `\n\n(${ranked.length - MAX_PAGES} further pages matched.)` : ''
  // "204 of the vault's pages matched" was true and told the reader nothing, because a page
  // that carries one common term is a match: what is worth saying is how many came back and
  // that the rest scored lower.
  const shown = Math.min(ranked.length, MAX_PAGES)
  return `The ${shown} best of ${ranked.length} pages that mention any of these terms, highest first. Read one in full before stating facts about what it covers.\n\n${out.join('\n\n')}${more}`
}

// ---------------------------------------------------------------------------------------
// Failure mode 3: a claim the user contradicts in conversation and nothing records
// ---------------------------------------------------------------------------------------

// $.model.classify's own prompt is fixed — it hands the model the text and the labels and
// takes back one of them — so these labels ARE the classifier's prompt. They are spelled out
// here, in the file, so the next person who finds a miss can argue with the wording instead of
// guessing at it. The second label exists because the costly false positive is a change of
// mind ("no, do the other one first"), which is an instruction about work and not a claim
// about the world; the ingest pipeline must never be handed one as a correction.
const LABELS = [
  "correction: the user's reply says that something the agent just stated as fact is wrong — flatly (「不對」, 「錯了」, 「不是這樣」, \"no, that is wrong\", \"that is not right\") or by stating a fact that contradicts the agent's",
  'instruction: the user\'s reply asks for work, gives a new task, or changes their mind about what to do next — including a brusque "no" about an approach, a plan or a preference rather than about a stated fact',
  "other: the user's reply is a question, an acknowledgement, more detail about the task, or anything that does not say a stated fact was wrong",
] as const

// A flat contradiction ("每小時跑一次") is only a correction against what it contradicts, so
// both turns are classified together; labelling the reply alone would make every bare fact
// look like an instruction.
const pair = (claim: string, said: string): string =>
  `The agent said:\n${claim}\n\nThe user replied:\n${said}`

// The gate. This hook runs on every prompt and $.model.classify is a model call, so only
// local tests may decide whether to make it. What each condition costs in recall:
//
//   - the prompt is at most 300 characters. A correction is short; a paragraph is a briefing.
//     Cost: a long correction that explains what is actually true, with its evidence, is
//     missed — and those are the most valuable ones. The session digest still carries it to
//     the next ingest, just without this file pointing at it.
//   - the session was idle, so the prompt answers a finished turn. Cost: a correction typed
//     over a running turn is missed, because the agent had not finished saying the thing being
//     corrected and "the immediately preceding turn" is not yet settled.
//   - the last message is the assistant's, at least 40 characters, and does not end in a
//     question mark, since a question is not a claim. Cost: a short claim ("Yes, it is on
//     main.") is missed, and so is a correction of something said two or more turns back.
//   - the prompt was typed by a person (see TYPED_BY_A_PERSON). Cost: nothing worth counting;
//     a prompt a host or a peer submitted was never the user's words to begin with.
//   - the prompt is not a slash command or a bare @mention. Cost: nothing worth counting.
const MAX_CORRECTION_CHARS = 300
const MIN_CLAIM_CHARS = 40

const priorClaim = (messages: readonly SessionMessage[]): string | undefined => {
  const last = messages.at(-1)
  if (last === undefined || last.role !== 'assistant') return undefined
  const text = last.text.trim()
  if (text.length < MIN_CLAIM_CHARS) return undefined
  if (/[?？]$/.test(text)) return undefined
  return text
}

// Every verbatim thing written below goes through the vault's own secret gate first, because a
// prompt may hold a credential and this file is the one place a prompt is copied to disk. The
// same redacted text is what reaches the classifier, so a credential never leaves the machine
// either; nothing here is logged, for the same reason.
const redact = async ($: EngineInterface, text: string): Promise<string> => {
  const { exitCode, stdout } = await $.process.run(
    [`${$.plugin.root}/scripts/secret-gate.sh`, '--redact'],
    { stdin: text, timeoutMs: 15000 },
  )
  // A gate that did not run is not a reason to write the raw text: drop the candidate.
  if (exitCode !== 0) throw new Error('secret gate did not run')
  return stdout.replace(/\n+$/, '')
}

// The claim is cut at the same length for the classifier and for the file: a model call whose
// size is the agent's last answer is not a free hook, and the transcript still has the whole.
const MAX_CLAIM_CHARS = 1200
const cut = (text: string): string =>
  text.length > MAX_CLAIM_CHARS ? `${text.slice(0, MAX_CLAIM_CHARS)}\n\n(cut here; the rest is in the session transcript)` : text

const candidate = (date: string, session: string, said: string, claim: string): string =>
  `---
kind: correction-candidate
date: ${date}
session: ${session}
---

A prompt.submit hook classified the message below as a correction of the claim beneath it.
It is a candidate, not a finding: no page was edited and no conflict was resolved, because
/brain:ingest is the only thing that files a fact and finish.sh is the only write path into
a vault.

The user's own words outrank every digest — ingest step 2 puts a human's correction above
everything — but they name no page. Find the page or pages carrying the claim, and run
restated.sh before rewriting one of them: a wrong claim is rarely written once, and a
correction applied to one page and not its restatements produces the same wrong answer again.

## The user said, verbatim

${said}

## What the agent had just said

${claim}
`

// The candidate quotes its text as the user's own words, so only an origin that is a person
// typing may produce one: the terminal, the Remote Control bridge (a phone or web client), and
// an unattested same-user channel. `sdk` is excluded along with the rest because it is the
// headless host's own turn — which is what auto-ingest runs in, and a run of the ingest skill
// must not be able to file itself a correction.
const TYPED_BY_A_PERSON = ['composer', 'bridge', 'unclassified']

const note = async (
  $: EngineInterface,
  text: string,
  turnId: string | undefined,
  origin: string,
): Promise<void> => {
  const said = text.trim()
  if (said.length === 0 || said.length > MAX_CORRECTION_CHARS) return
  if (turnId !== undefined) return
  if (!TYPED_BY_A_PERSON.includes(origin)) return
  if (said.startsWith('/') || said.startsWith('@')) return

  const messages = await $.session.messages()
  const claim = priorClaim(messages)
  if (claim === undefined) return

  // Resolved before the model call, so a session outside every routed tree costs nothing.
  const vault = await resolveVault($)
  if (vault === undefined) return

  const [redactedSaid, redactedClaim] = [await redact($, said), cut(await redact($, claim))]
  const label = await $.model.classify(pair(redactedClaim, redactedSaid), LABELS)
  if (label === undefined || !label.startsWith('correction:')) return

  const now = new Date(await $.clock.now()).toISOString()
  const date = now.slice(0, 10)
  const session = await $.session.id()
  // One file per correction, under one directory because a week of them is a list and not a
  // handful, and named with the second and the session so two sessions correcting at once
  // cannot overwrite each other. .state/ is per-machine and gitignored, which is where a
  // candidate belongs until a human or an ingest run decides what it means.
  const stamp = `${now.slice(11, 19).replace(/:/g, '')}-${session.slice(0, 8)}`
  await $.fs.write(
    `${vault}/.state/corrections/${date}-${stamp}.md`,
    candidate(date, session, redactedSaid, redactedClaim),
  )
  // The user is told a file landed in their vault, without their words in the line: a hook
  // that writes to the vault in silence is a hook nobody can audit.
  await $.ui.toast('brain: correction recorded for the next ingest')
}

// The engine exposes a tool registered by a plugin as `mcp__<plugin>__<name>`, so this
// constant and the `name` handed to $.tool.register are two halves of one fact. The short
// name is derived from the full one because keeping them as separate literals is what broke:
// this module began as a dev mod called `brain-query`, and when it moved into the `brain`
// plugin the prefix changed while the hardcoded matcher did not — the tool registered and no
// hook answered its calls. The tests shared the same wrong literal, so they passed.
export const TOOL = 'mcp__brain__search'
const TOOL_NAME = TOOL.split('__')[2] as string

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.tool.register({
      name: TOOL_NAME,
      description: DESCRIPTION,
      inputSchema: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description:
              'Distinctive words to look for: a ticket id, a repository, a service, a person, a feature name. A rare word decides the ranking and a word most pages carry barely moves it, so a whole question works as a query — its ordinary words simply do no work.',
          },
        },
        required: ['query'],
      },
    })
    return next(e)
  })

  on('tool.call', { tool: TOOL }, async ($, e) => {
    // A RegExp matcher leaves `e` the union of every tool's event, and a registered
    // tool's arguments ride the variant's string index signature rather than a field
    // the union shares. Both shapes are read because the harness hands them over
    // under `input` while a model's call flattens them onto the event.
    const bag = e as unknown as { input?: { query?: unknown }; query?: unknown }
    const query =
      typeof bag.input?.query === 'string'
        ? bag.input.query
        : typeof bag.query === 'string'
          ? bag.query
          : ''
    return { result: await search($, query) }
  }).catch(() => ({
    // This hook answers the call itself, so without a handler a failure or an overrun would
    // leave the model's call hitting a tool with nothing beneath it. Say what happened and
    // what to do instead.
    result: 'The vault search did not run. Read a page by path, or run /brain:query.',
  }))

  on('prompt.submit', async ($, e, next) => {
    // The work happens before the prompt enters, so the candidate is on disk before the agent
    // answers over the claim; when the gate fires the user waits one small-model completion.
    try {
      await note($, e.text, e.turnId, e.origin.kind)
    } catch {
      // A prompt is never lost to this hook. Classification, the secret gate and the write are
      // all optional work, and nothing about recording a correction is worth dropping what the
      // user typed.
    }
    return next(e)
  }).catch(($, e, next) => next(e))
  // The try/catch above cannot catch a budget overrun — a slow classifier, a vault on a
  // sleeping disk — and this handler can, so the prompt enters either way.
}
