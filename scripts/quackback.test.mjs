// node --test scripts/quackback.test.mjs
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { changelogEntry, moves, plan, postIds } from './quackback.mjs'

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

const issue = (extra = {}) => ({ number: 7, state: 'open', state_reason: null, body: `Quackback: ${A}`, ...extra })

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
