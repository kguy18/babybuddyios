// node --test scripts/asc.test.mjs
// The pure parts of asc.mjs. Nothing here touches the network.
import assert from 'node:assert/strict'
import { generateKeyPairSync, verify } from 'node:crypto'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import {
  appStoreNotes, automatic, buildRows, cardWarnings, commands, compareDotted, jwt, latestUpload, loadConfig,
  marketingVersion, missingReviewInfo, nextBuild, NOTES_LIMIT, parseArgs, prBullets, releaseBody,
  sections, statusLine, validateNotes, whatToTest,
} from './asc.mjs'

const part = (s) => JSON.parse(Buffer.from(s, 'base64url').toString())

test('jwt has the header and claims Apple expects and a raw ES256 signature', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const token = jwt({ keyId: 'KEY', issuerId: 'ISS', privateKey, now: 1_000_000_000_000 })
  const [head, claims, sig] = token.split('.')
  assert.deepEqual(part(head), { alg: 'ES256', kid: 'KEY', typ: 'JWT' })
  assert.deepEqual(part(claims), { iss: 'ISS', iat: 1_000_000_000, exp: 1_000_001_200, aud: 'appstoreconnect-v1' })
  assert.equal(Buffer.from(sig, 'base64url').length, 64)
  assert.ok(verify('sha256', Buffer.from(`${head}.${claims}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url')))
})

test('the committed appstore.json loads, and a missing key is named', () => {
  const config = loadConfig()
  assert.match(config.projectYml, /(^|\/)project\.yml$/)
  assert.equal(typeof config.bundleId, 'string')
  const dir = mkdtempSync(join(tmpdir(), 'asc-config-'))
  writeFileSync(join(dir, 'a.json'), JSON.stringify({ bundleId: 'x', projectYml: 'p', appDir: 'A' }))
  assert.throws(() => loadConfig(join(dir, 'a.json')), /"notesFile" is missing/)
})

test('parseArgs refuses bad input before the network', () => {
  assert.deepEqual(parseArgs(['builds']), { command: 'builds', args: [] })
  assert.throws(() => parseArgs(['builds', '0']), /not a count/)
  assert.throws(() => parseArgs(['builds', '5', 'x']), /not a marketing version/)
  assert.deepEqual(parseArgs(['next-build', '1.2.0']).args, ['1.2.0'])
  assert.throws(() => parseArgs(['next-build', 'v1']), /not a marketing version/)
  assert.throws(() => parseArgs(['test-notes', '1.1', 'v1', 'f']), /not a build number/)
  assert.throws(() => parseArgs(['distribute', '1.1', '3']), /usage/)
  assert.deepEqual(parseArgs(['status', '1.0', '--json']).args, ['1.0', '--json'])
  assert.throws(() => parseArgs(['status', '1.0', '--jsn']), /usage/)
  assert.throws(() => parseArgs(['status']), /usage/)
  assert.throws(() => parseArgs(['toString']), /usage/)
  assert.deepEqual(parseArgs(['attach', '1.1']).args, ['1.1'])
  assert.deepEqual(parseArgs(['attach', '1.1', '4']).args, ['1.1', '4'])
  assert.deepEqual(parseArgs(['what-to-test', '2026-09-23T11:25:00Z']).args, ['2026-09-23T11:25:00Z'])
  assert.throws(() => parseArgs(['what-to-test', 'yesterday']), /not a date/)
  assert.deepEqual(parseArgs(['marketing-version', '-']).args, ['-'])
})

test('marketingVersion reads project.yml in its quoted and bare forms', () => {
  assert.equal(marketingVersion('settings:\n  base:\n    MARKETING_VERSION: "1.2"\n    CURRENT_PROJECT_VERSION: 1\n'), '1.2')
  assert.equal(marketingVersion('    MARKETING_VERSION: 1.2.3\n'), '1.2.3')
  assert.equal(marketingVersion("    MARKETING_VERSION: '2.0'  # set by the version PR\n"), '2.0')
  assert.equal(marketingVersion('name: App\n'), '')
})

test('dotted numbers sort by part, not by text', () => {
  assert.deepEqual(['1.10', '1.2', '1.9.1', '1'].sort(compareDotted), ['1', '1.2', '1.9.1', '1.10'])
})

test('nextBuild is one more than the highest whole build, or 1', () => {
  assert.equal(nextBuild([]), 1)
  assert.equal(nextBuild([{ build: '4' }]), 5)
  assert.equal(nextBuild([{ build: '2' }, { build: '10' }, { build: '9' }]), 11)
  assert.equal(nextBuild([{ build: 'abc' }, { build: '3' }]), 4)
  // An older date-time build still gets a whole number that sorts above it.
  const next = nextBuild([{ build: '20260923.1530' }])
  assert.equal(next, 20260924)
  assert.ok(compareDotted(String(next), '20260923.1530') > 0)
})

test('buildRows puts the newest version, then the newest build, first, with review state', () => {
  const b = (id, version, pre, review) => ({
    id, attributes: { version, processingState: 'VALID', uploadedDate: `2026-09-2${id}T00:00:00-07:00` },
    relationships: { preReleaseVersion: { data: { id: pre } }, ...(review && { betaAppReviewSubmission: { data: { id: review } } }) },
  })
  const rows = buildRows({
    data: [b('1', '1', 'p1'), b('2', '1', 'p2', 'r1'), b('3', '2', 'p1')],
    included: [{ type: 'preReleaseVersions', id: 'p1', attributes: { version: '1.0' } },
      { type: 'preReleaseVersions', id: 'p2', attributes: { version: '1.1' } },
      { type: 'betaAppReviewSubmissions', id: 'r1', attributes: { betaReviewState: 'APPROVED' } }],
  })
  assert.deepEqual(rows.map((r) => `${r.version}/${r.build}/${r.review}`), ['1.1/1/APPROVED', '1.0/2/', '1.0/1/'])
  assert.equal(latestUpload(rows), '2026-09-23T00:00:00-07:00')
  assert.equal(latestUpload([]), '')
})

test('statusLine says when there is no version', () => {
  assert.equal(statusLine('1.0', { state: 'READY_FOR_DISTRIBUTION', build: '3' }), '1.0: READY_FOR_DISTRIBUTION, build 3')
  assert.equal(statusLine('1.1', { state: 'PREPARE_FOR_SUBMISSION', build: null }), '1.1: PREPARE_FOR_SUBMISSION, build none attached')
  assert.equal(statusLine('1.2', { state: null, build: null }), '1.2: no iOS App Store version yet')
})

test('automatic is only an internal group with access to all builds', () => {
  assert.equal(automatic({ attributes: { isInternalGroup: true, hasAccessToAllBuilds: true } }), true)
  assert.equal(automatic({ attributes: { isInternalGroup: true, hasAccessToAllBuilds: false } }), false)
  assert.equal(automatic({ attributes: { isInternalGroup: false, hasAccessToAllBuilds: true } }), false)
})

test('missingReviewInfo asks for sign-in only when sign-in is required', () => {
  const full = { contactFirstName: 'A', contactLastName: 'B', contactPhone: '555', contactEmail: 'a@example.com' }
  assert.deepEqual(missingReviewInfo(full), [])
  assert.deepEqual(missingReviewInfo({}), ['First name', 'Last name', 'Phone number', 'Email'])
  assert.deepEqual(missingReviewInfo({ ...full, demoAccountRequired: true, demoAccountName: 'x' }), ['Password'])
})

// Release notes, in the shape docs/release-notes.md documents.
const F = '```'
const section = (version, appstore, whatsnew) =>
  `## ${version}\n\n${F}appstore\n${appstore}\n${F}\n` + (whatsnew === undefined ? '' : `\n${F}whatsnew\n${whatsnew}\n${F}\n`)
const STORE = '#New\n- I added a thing, with "quotes" and arrows.\n\n#Fixed\n- The other thing works now.'
const FILE = `# Release notes\n\n    #New\n    - <a sentence>\n\n${section('1.1', STORE)}\n${section('1.0.1', '#Fixed\n- One fix.')}`

test('the App Store text comes out exactly as written', () => {
  assert.deepEqual(validateNotes(FILE), [])
  assert.deepEqual(sections(FILE).map((s) => s.version), ['1.1', '1.0.1'])
  assert.equal(appStoreNotes(FILE, '1.1'), STORE)
  assert.equal(appStoreNotes(FILE.replace(/\n/g, '\r\n'), '1.1'), STORE)
})

test('a file with no sections is valid, and a version without one has no notes', () => {
  assert.deepEqual(validateNotes('# Release notes\n\nThe format.\n'), [])
  assert.throws(() => appStoreNotes('# Release notes\n', '1.1'), /1\.1: no section in the release notes/)
})

test('a first version may be a plain paragraph; every later one starts with a header', () => {
  const paragraph = 'The first release. Sign in with Apple to start.'
  assert.deepEqual(validateNotes(section('1.0', paragraph)), [])
  assert.deepEqual(validateNotes(section('1.1', paragraph)), ['1.1: the `appstore` block must start with one of #New, #Improved, #Fixed'])
  assert.match(validateNotes(section('1.0', 'What 1.0 is.'))[0], /repeats the version number/)
})

test('validateNotes refuses what App Store Connect or the format would not take', () => {
  assert.deepEqual(validateNotes(`## 1.2\n\n${F}\n#New\n- x\n${F}\n`), ['1.2: no `appstore` block'])
  assert.deepEqual(validateNotes(section('1.2', '  ')), ['1.2: the `appstore` block is empty'])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x') + section('1.2', '#Fixed\n- y')), ['1.2: more than one section'])
  assert.deepEqual(validateNotes(section('1.1', '#New\n- x') + section('1.2', '#Fixed\n- y')), ['1.2: below 1.1, but the file is newest first'])
  for (const heading of ['## v1.2', '##1.2', '## 1.2 beta', '## 1']) {
    assert.match(validateNotes(section('1.2', 'x').replace('## 1.2', heading))[0], /malformed heading/, heading)
  }
  assert.deepEqual(validateNotes(section('1.2', '#New\n' + '→'.repeat(NOTES_LIMIT - 5))), [])
  assert.match(validateNotes(section('1.2', '#New\n' + '→'.repeat(NOTES_LIMIT - 4)))[0], /4001 characters/)
  assert.deepEqual(validateNotes(section('1.2', '#Fixed\n# New\n- x')), ['1.2: "# New" is not one of #New, #Improved, #Fixed'])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- Doses of 1.25 mg and 11.2 cm read right.')), [])
})

test('the whatsnew block is required and checked only when appstore.json turns it on', () => {
  const card = '#New\n- sync | Sync with Pro | Encrypted before it leaves the phone.\n- new | No body\n#Fixed\n- A plain line, no icon'
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x')), [])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x'), { whatsNew: true }), ['1.2: no `whatsnew` block'])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', card), { whatsNew: true }), [])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', card), { whatsNew: ['sync', 'new'] }), [])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', '#New\n- bell | Push'), { whatsNew: ['sync', 'new'] }),
    ['1.2: unknown icon "bell" in "- bell | Push" (one of sync, new)'])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', '#New\n- sync |'), { whatsNew: true }), ['1.2: no title in "- sync |"'])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', ' '), { whatsNew: true }), ['1.2: the `whatsnew` block is empty'])
  // Only the newest section must have one, so older sections written before it was on still pass.
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', card) + section('1.1', '#New\n- x'), { whatsNew: true }), [])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x') + section('1.1', '#New\n- x', card), { whatsNew: true }), ['1.2: no `whatsnew` block'])
})

test('a card row over its limits is a warning, on the newest section only', () => {
  const long = `#New\n- new | ${'t'.repeat(33)} | fine\n- new | fine | ${'b'.repeat(91)}\n- new | ${'t'.repeat(32)} | ${'b'.repeat(90)}\n#Fixed\n- ${'a plain line of any length '.repeat(6)}`
  const warnings = cardWarnings(section('1.2', '#New\n- x', long) + section('1.1', '#New\n- x', long))
  assert.equal(warnings.length, 2)
  assert.match(warnings[0], /^1\.2: card row is over 32 \(title 33\) or 90 \(body 4\)/)
  assert.match(warnings[1], /\(title 4\) or 90 \(body 91\)/)
  assert.deepEqual(cardWarnings(section('1.2', '#New\n- x')), [])
  assert.deepEqual(validateNotes(section('1.2', '#New\n- x', long), { whatsNew: true }), [])
  // The appstore block is found by its label, not its position.
  const swapped = `## 2.0\n\n${F}whatsnew\n#New\n- new | Card\n${F}\n\n${F}appstore\n#New\n- Store.\n${F}\n`
  assert.equal(appStoreNotes(swapped, '2.0', { whatsNew: true }), '#New\n- Store.')
})

test('the GitHub Release body turns headers into Markdown and ends with the build', () => {
  assert.equal(releaseBody(FILE, '1.1', '7'), '### New\n- I added a thing, with "quotes" and arrows.\n\n### Fixed\n- The other thing works now.\n\nBuild: 7\n')
  assert.equal(releaseBody(FILE, '1.0.1'), '### Fixed\n- One fix.\n')
})

// What to Test, from `gh pr list --json number,title,body,labels,mergedAt,files`.
const pr = (n, mergedAt, bullets, { labels = [], files = [`AppName/Views/V${n}.swift`] } = {}) => ({
  number: n, title: `PR ${n}`, mergedAt, labels: labels.map((name) => ({ name })), files: files.map((path) => ({ path })),
  body: `## Summary\nStuff.\n\n## What to test\n${bullets.map((b) => `- ${b}`).join('\n')}\n-\n<!-- placeholder -->\n\n## Notes\n- not this`,
})

test('prBullets reads only the What to test section and skips the template placeholders', () => {
  assert.deepEqual(prBullets(pr(1, '2026-01-01T00:00:00Z', ['Tap X. Y shows.']).body), ['Tap X. Y shows.'])
  assert.deepEqual(prBullets('no section'), [])
  assert.deepEqual(prBullets(null), [])
})

test('HTML comments from the current template are not text, even across lines', () => {
  const template = readFileSync(new URL('../.github/pull_request_template.md', import.meta.url), 'utf8')
  assert.equal(whatToTest([{ ...pr(1, '2026-01-02T00:00:00Z', []), body: template }], { since: '2026-01-01T00:00:00Z', appDir: 'AppName' }), 'PR 1')
  const filled = '## What to test\n\n<!-- Two to four bullets.\n- not a bullet\nTestFlight. -->\n\n- Tap Save.\n- The row appears.\n'
  assert.deepEqual(prBullets(filled), ['Tap Save.', 'The row appears.'])
})

test('whatToTest lists app PRs merged after the last upload, newest first, without internal ones', () => {
  const prs = [
    pr(1, '2026-01-01T00:00:00Z', ['Old.']),
    pr(2, '2026-01-03T00:00:00Z', ['Open Settings. It shows ✓ Saved.']),
    pr(3, '2026-01-04T00:00:00Z', ['Hidden.'], { labels: ['internal'] }),
    pr(4, '2026-01-05T00:00:00Z', ['Web only.'], { files: ['web/index.html'] }),
    pr(5, '2026-01-06T00:00:00Z', ['Newest.']),
    pr(6, '2026-01-07T00:00:00Z', ['No file list, so it counts.'], { files: [] }),
  ]
  // A zone offset and UTC compare as instants: 2026-01-01T17:00-08:00 is after PR 1.
  assert.equal(whatToTest(prs, { since: '2026-01-01T17:00:00-08:00', appDir: 'AppName' }),
    'PR 6\n- No file list, so it counts.\n\nPR 5\n- Newest.\n\nPR 2\n- Open Settings. It shows check Saved.')
  assert.equal(whatToTest(prs, { since: '2026-02-01T00:00:00Z', appDir: 'AppName' }), 'Small fixes and polish.')
  assert.equal(whatToTest([]), 'Small fixes and polish.')
})

test('whatToTest fits 4000 characters by dropping the oldest PRs whole', () => {
  const long = (n, day) => pr(n, `2026-01-${day}T00:00:00Z`, ['x'.repeat(1500)])
  const text = whatToTest([long(1, '01'), long(2, '02'), long(3, '03')], { appDir: 'AppName' })
  assert.ok([...text].length <= NOTES_LIMIT)
  assert.match(text, /^PR 3\n/)
  assert.match(text, /PR 2\n/)
  assert.doesNotMatch(text, /PR 1\n/)
  assert.match(text, /\(and earlier changes\)$/)
  // One PR alone over the limit is cut at it.
  assert.equal([...whatToTest([pr(9, '2026-01-01T00:00:00Z', ['y'.repeat(5000)])])].length, NOTES_LIMIT)
})

test('whats-new sends nothing for a first version', async () => {
  const lines = []
  const realFetch = globalThis.fetch
  const realLog = console.log
  globalThis.fetch = async (url) => { throw new Error(`unexpected ${url}`) }
  console.log = (line) => lines.push(line)
  try {
    await commands['whats-new']('1.0')
  } finally {
    globalThis.fetch = realFetch
    console.log = realLog
  }
  assert.deepEqual(lines, ["1.0: the first version has no What's New in App Store Connect. Nothing was sent."])
})
