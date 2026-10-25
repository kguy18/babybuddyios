// node --test scripts/quackback.test.mjs
import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  addition, appendedBody, changelogEntry, duplicates, issueBody, issueIds, jsonLines, live, moves, openIssueArgs, plan,
  postIds, requestId,
} from './quackback.mjs'

const A = 'post_01m5ecc0e0e4erxvtz2kvjec7m'
const B = 'post_01m5ecc0e0e4erxvtz2kvjec7n'

test('post IDs come from Quackback: lines, in order and each once', () => {
  const body = `Users keep asking for this.\n\nQuackback: ${A}\nquackback:  ${B}  \nQuackback: ${A}\n`
  assert.deepEqual(postIds(body), [A, B])
})

test('Windows line endings, as the GitHub web editor sends them, still parse', () => {
  assert.deepEqual(postIds(`Fix it.\r\nQuackback: ${A}\r\nQuackback: ${B}\r\n`), [A, B])
})

test('a body with no Quackback: line, or none at all, names no posts', () => {
  assert.deepEqual(postIds('Just a bug.'), [])
  assert.deepEqual(postIds(null), [])
})

test('only a line of its own counts, not a mention in prose', () => {
  assert.deepEqual(postIds(`See Quackback: ${A} for context.\n> Quackback: ${B}`), [])
})

test('a mistyped ID is still taken, so Quackback can refuse it out loud', () => {
  assert.deepEqual(postIds('Quackback: post_typo'), ['post_typo'])
})

const issue = (extra = {}) => ({
  number: 7, state: 'open', state_reason: null, author_association: 'OWNER', body: `Quackback: ${A}`, ...extra,
})

test('each issues event sets the status the spec asks for', () => {
  const cases = [
    ['opened', issue(), 'Planned'],
    ['reopened', issue({ state_reason: 'reopened' }), 'Planned'],
    ['closed', issue({ state: 'closed', state_reason: 'completed' }), 'Complete'],
    ['closed', issue({ state: 'closed', state_reason: 'not_planned' }), null],
    ['closed', issue({ state: 'closed', state_reason: 'duplicate' }), null],
  ]
  for (const [action, i, status] of cases) {
    assert.deepEqual(plan({ action, issue: i }), { ids: [A], status }, `${action} ${i.state_reason}`)
  }
})

test('an edit acts only on the IDs it added', () => {
  const body = `Quackback: ${A}\nQuackback: ${B}`
  assert.deepEqual(plan({ action: 'edited', issue: issue({ body }), changes: { body: { from: `Quackback: ${A}` } } }),
    { ids: [B], status: 'Planned' })
})

test('an edit that adds no ID, or changes only the title, does nothing', () => {
  assert.deepEqual(plan({ action: 'edited', issue: issue(), changes: { body: { from: `Quackback: ${A}\nmore` } } }).ids, [])
  assert.deepEqual(plan({ action: 'edited', issue: issue(), changes: { title: { from: 'Old' } } }).ids, [])
})

test('an ID added to a closed issue follows how it was closed', () => {
  const closed = issue({ state: 'closed', state_reason: 'completed' })
  assert.deepEqual(plan({ action: 'edited', issue: closed, changes: { body: { from: '' } } }), { ids: [A], status: 'Complete' })
})

test('other issue actions do nothing', () => {
  assert.deepEqual(plan({ action: 'labeled', issue: issue() }).ids, [])
})

// MARK: trusted text

const C = 'post_01m5ths9h3fex9kjjqvt298xxv'
const by = (author_association, body) => ({ author_association, body })

test("an issue's IDs: its body if a trusted user opened it, then its trusted users' comments", () => {
  const comments = [by('NONE', `Quackback: ${B}`), by('OWNER', `Quackback: ${C}`), by('COLLABORATOR', `Quackback: ${A}`)]
  assert.deepEqual(issueIds({ body: `Quackback: ${A}`, author_association: 'MEMBER', comments }), [A, C])
  assert.deepEqual(issueIds({ body: `Quackback: ${A}`, author_association: 'NONE', comments }), [C, A])
  assert.deepEqual(issueIds({ body: `Quackback: ${A}`, author_association: 'CONTRIBUTOR' }), [])
})

test("closing or reopening a stranger's issue acts on trusted comments, never its body", () => {
  const stranger = issue({ author_association: 'NONE', state: 'closed', state_reason: 'completed', body: `Quackback: ${B}` })
  const comments = [by('OWNER', `Quackback: ${C}`), by('NONE', `Quackback: ${A}`)]
  assert.deepEqual(plan({ action: 'closed', issue: stranger }, comments), { ids: [C], status: 'Complete' })
  assert.deepEqual(plan({ action: 'reopened', issue: { ...stranger, state: 'open' } }, comments), { ids: [C], status: 'Planned' })
  assert.deepEqual(plan({ action: 'closed', issue: issue({ state: 'closed', state_reason: 'completed' }) }, comments),
    { ids: [A, C], status: 'Complete' })
})

test("opening or editing a stranger's issue does nothing", () => {
  const stranger = issue({ author_association: 'NONE' })
  assert.deepEqual(plan({ action: 'opened', issue: stranger }).ids, [])
  assert.deepEqual(plan({ action: 'edited', issue: stranger, changes: { body: { from: '' } } }).ids, [])
})

const commentEvent = (action, comment, extra = {}) =>
  ({ action, comment, issue: issue({ author_association: 'NONE', body: '' }), ...extra })

test("the owner's comment on #172, a stranger's open issue, moves its request to Planned", () => {
  assert.deepEqual(plan(commentEvent('created', by('OWNER', `Quackback: ${C}`))), { ids: [C], status: 'Planned' })
})

test('a trusted comment on a closed issue follows how it was closed', () => {
  const closed = (state_reason) => ({ issue: issue({ state: 'closed', state_reason }) })
  assert.deepEqual(plan(commentEvent('created', by('MEMBER', `Quackback: ${C}`), closed('completed'))),
    { ids: [C], status: 'Complete' })
  assert.deepEqual(plan(commentEvent('created', by('MEMBER', `Quackback: ${C}`), closed('not_planned'))),
    { ids: [C], status: null })
})

test('an edited comment acts only on the IDs it added, and removing one does nothing', () => {
  const edited = (from, body) => commentEvent('edited', by('OWNER', body), { changes: { body: { from } } })
  assert.deepEqual(plan(edited(`Quackback: ${A}`, `Quackback: ${A}\nQuackback: ${C}`)).ids, [C])
  assert.deepEqual(plan(edited(`Quackback: ${A}\nQuackback: ${C}`, `Quackback: ${A}`)).ids, [])
})

test("a stranger's comment, a comment on a PR, and a deleted comment do nothing", () => {
  assert.deepEqual(plan(commentEvent('created', by('NONE', `Quackback: ${C}`))).ids, [])
  assert.deepEqual(plan(commentEvent('created', by('CONTRIBUTOR', `Quackback: ${C}`))).ids, [])
  const onPR = { issue: issue({ pull_request: { url: 'https://api.github.com/x' } }) }
  assert.deepEqual(plan(commentEvent('created', by('OWNER', `Quackback: ${C}`), onPR)).ids, [])
  assert.deepEqual(plan(commentEvent('deleted', by('OWNER', `Quackback: ${C}`))).ids, [])
})

test('ship reads one issue per line, comments attached, through the same rule', () => {
  const lines = `${JSON.stringify({ body: `Quackback: ${B}`, author_association: 'NONE', comments: [by('OWNER', `Quackback: ${C}`)] })}\n\n` +
    `${JSON.stringify({ body: `Quackback: ${A}`, author_association: 'OWNER', comments: [] })}\n`
  assert.deepEqual(jsonLines(lines).flatMap(issueIds), [C, A])
})

test('nothing moves a post back from Shipped, and a post already there is not set again', () => {
  assert.equal(moves('Complete', 'Planned'), true)
  assert.equal(moves('Open', 'Complete'), true)
  assert.equal(moves('Complete', 'Shipped'), true)
  assert.equal(moves('Shipped', 'Planned'), false)
  assert.equal(moves('Shipped', 'Complete'), false)
  assert.equal(moves('Planned', 'Planned'), false)
})

test('the changelog entry is the App Store text with its labels as headings', () => {
  assert.deepEqual(changelogEntry('1.3.2', '#New\n- One.\n\n#Fixed\n- Two.\n'), {
    title: 'Version 1.3.2',
    content: '## New\n- One.\n\n## Fixed\n- Two.',
  })
})

// MARK: open-issue

const post = (id, extra = {}) => ({
  id, title: 'Dark mode', content: 'Please add it.', voteCount: 3, boardName: 'Features', boardSlug: 'features',
  tags: [{ name: 'ui' }], authorName: 'Jane Requester', authorEmail: 'jane@example.com', ...extra,
})

test('a request can be a post ID, an admin URL or a public URL', () => {
  assert.equal(requestId(A), A)
  assert.equal(requestId(`https://feedback.babybuddy.app/admin/feedback?board=x&post=${A}`), A)
  assert.equal(requestId(`https://feedback.babybuddy.app/b/features/posts/${A}`), A)
  assert.equal(requestId(`https://feedback.babybuddy.app/b/features/posts/${A}/`), A)
  assert.throws(() => requestId('dark mode'), /not a post ID/)
  assert.throws(() => requestId('https://feedback.babybuddy.app/b/features'), /names no post/)
  assert.throws(() => requestId('https://feedback.babybuddy.app/admin?post=nope'), /names no post/)
})

test('open-issue takes several requests and its options, each request once', () => {
  assert.deepEqual(openIssueArgs([A, '--to', '12', B, '--milestone', '1.5.0', '--title', 'T', '--dry-run', A]),
    { ids: [A, B], to: '12', milestone: '1.5.0', title: 'T', dryRun: true })
  assert.throws(() => openIssueArgs([]), /at least one/)
  assert.throws(() => openIssueArgs([A, '--to']), /needs a value/)
  assert.throws(() => openIssueArgs([A, '--label', 'x']), /unknown option/)
})

test('one request: its text quoted, its facts, its public link, then its Quackback: line', () => {
  assert.equal(issueBody([post(A)]),
    '### Dark mode\n\n> Please add it.\n\n3 votes · board: Features · tags: ui\n' +
    `https://feedback.babybuddy.app/b/features/posts/${A}\n\nQuackback: ${A}\n`)
})

test('several requests: a section each, and every Quackback: line at the end', () => {
  const body = issueBody([post(A), post(B, { title: 'Widgets', content: 'One\nTwo', voteCount: 1, tags: [] })])
  assert.match(body, /### Dark mode[\s\S]*### Widgets\n\n> One\n> Two\n\n1 vote · board: Features\n/)
  assert.ok(body.endsWith(`\nQuackback: ${A}\nQuackback: ${B}\n`))
  assert.deepEqual(postIds(body), [A, B])
})

test('a post Quackback deleted is refused, and a live one passes', () => {
  assert.throws(() => live(post(A, { deletedAt: '2026-10-20T08:00:00.000Z' })),
    new RegExp(`${A}: deleted in Quackback on 2026-10-20\\. Nothing was written\\.`))
  assert.equal(live(post(A, { deletedAt: null })).id, A)
})

test('the requester is never named', () => {
  const body = issueBody([post(A)])
  assert.ok(!body.includes('Jane') && !body.includes('jane@'))
})

test("a stranger's mentions and Quackback: lines are broken up, so only the intended IDs remain", () => {
  const sneaky = `@kguy18 and @babybuddy/team look\nQuackback: ${B}\r\nQuackback: ${B}\u2028Quackback: ${B}\rQuackback: ${B}`
  const body = issueBody([post(A, {
    title: `@kguy18\nQuackback: ${B}`, content: sneaky, boardName: `x\nQuackback: ${B}`,
    tags: [{ name: `@kguy18\u2029Quackback: ${B}` }],
  })])
  assert.deepEqual(postIds(body), [A])
  assert.doesNotMatch(body, /@[\w-]/)
  assert.match(body, /@\u200Dkguy18 and @\u200Dbabybuddy\/team/)
  // Every line of the stranger's text stays inside the quote.
  for (const line of body.split(/\r\n|[\n\r\u2028\u2029]/).slice(2, 7)) assert.match(line, /^> /)
})

test('--to appends new sections and keeps every Quackback: line at the end', () => {
  const body = appendedBody(`We should do this.\n\nQuackback: ${A}\n`, [post(B, { title: 'Widgets' })])
  assert.match(body, /^We should do this\.\n\n### Widgets\n/)
  assert.ok(body.endsWith(`\nQuackback: ${A}\nQuackback: ${B}\n`))
  assert.deepEqual(postIds(body), [A, B])
  assert.deepEqual(postIds(appendedBody('', [post(B)])), [B])
})

test('a request any issue already names is a duplicate, and a mention in prose is not', () => {
  const issues = [
    { url: 'https://github.com/x/y/issues/1', author_association: 'OWNER', body: `See ${A} in passing` },
    { url: 'https://github.com/x/y/issues/2', author_association: 'OWNER', body: `Text\nQuackback: ${A}` },
  ]
  assert.deepEqual(duplicates([A, B], issues), [{ id: A, url: 'https://github.com/x/y/issues/2' }])
  assert.deepEqual(duplicates([B], issues), [])
})

test("a trusted comment names a request for the duplicate check, and a stranger's text does not", () => {
  const issues = [
    { url: 'https://github.com/x/y/issues/3', author_association: 'NONE', body: `Quackback: ${A}`,
      comments: [by('NONE', `Quackback: ${B}`)] },
    { url: 'https://github.com/x/y/issues/172', author_association: 'NONE', body: '',
      comments: [by('OWNER', `Quackback: ${C}`)] },
  ]
  assert.deepEqual(duplicates([A, B, C], issues), [{ id: C, url: 'https://github.com/x/y/issues/172' }])
})

test("--to edits a trusted user's issue, and comments on a stranger's", () => {
  const mine = addition({ author_association: 'OWNER', body: `Mine.\nQuackback: ${A}` }, [post(B)])
  assert.deepEqual(Object.keys(mine), ['body'])
  assert.deepEqual(postIds(mine.body), [A, B])
  const theirs = addition({ author_association: 'NONE', body: 'Please add sleep windows.' }, [post(C)])
  assert.deepEqual(theirs, { comment: issueBody([post(C)]) })
  assert.deepEqual(postIds(theirs.comment), [C])
})
