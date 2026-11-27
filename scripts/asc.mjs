#!/usr/bin/env node
// App Store Connect client and release-notes reader for the /kguydev:appstore skill
// and the release workflows. No dependencies, so it runs in CI with nothing
// installed. Per-repo values (bundle ID, paths) come from appstore.json at the
// repo root. The App Store Connect commands need ASC_KEY_ID, ASC_ISSUER_ID
// and ASC_KEY_P8_BASE64. scripts/asc runs a command with them loaded:
//
//   scripts/asc <command>
//
// App Store Connect:
//   builds [n] [version]             latest n builds: build, version, processing state, Beta App Review, uploaded
//   next-build <version>             one more than the highest build App Store Connect has for the version, or 1
//   last-upload                      when the newest build of any version was uploaded (empty if none)
//   wait-build <version> <build>     wait up to 30 minutes for the build to finish processing
//   test-notes <version> <build> <file>   set the build's What to Test (en-US) once it has processed
//   groups                           TestFlight groups: name, id, internal or external, automatic
//   distribute <version> <build> <group>  add a processed build to a group; after an external
//                                    group, submit it for Beta App Review once
//   status <version> [--json]        the App Store version's state and attached build
//   version <version>                find or create the iOS App Store version (manual release)
//   whats-new <version>              set its en-US What's New from the notes file (1.0 has none)
//   attach <version> [build]         attach a build; default the newest processed one of the version
//   submit <version>                 submit the version for App Review
//   review-attachment <version> <file>    upload a file to App Review Information's attachments,
//                                    replacing one with the same name
//
// No credentials needed:
//   validate                         check the notes file; warns when a card row is over its limit
//   notes <version>                  the version's `appstore` block, byte for byte
//   body <version> [build]           the GitHub Release body, ending `Build: <build>`
//   what-to-test [since]             TestFlight's What to Test from `gh pr list` JSON on stdin
//   marketing-version [file]         MARKETING_VERSION from project.yml (`-` reads stdin)
//
// RELEASE_NOTES=<path> makes validate, notes and body read another copy of the notes file.
//
// Nothing here prints a secret. Apple's error bodies carry no credential.

import { createHash, sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { basename, join } from 'node:path'
import { setTimeout as sleep } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const VERSION = /^\d+\.\d+(\.\d+)?$/
const BUILD = /^\d+(\.\d+)*$/

// MARK: config

/// appstore.json, with defaults for the optional keys. APPSTORE_JSON points at another copy (tests).
export function loadConfig(path = process.env.APPSTORE_JSON ?? join(ROOT, 'appstore.json')) {
  const config = { whatsNew: false, ...JSON.parse(readFileSync(path, 'utf8')) }
  for (const key of ['bundleId', 'projectYml', 'appDir', 'notesFile']) {
    if (typeof config[key] !== 'string' || !config[key]) throw new Error(`appstore.json: "${key}" is missing`)
  }
  return config
}
let cached
const config = () => (cached ??= loadConfig())
const repoPath = (relative) => join(ROOT, relative)

// MARK: arguments

const USAGE = {
  builds: ['[n]', '[version]'],
  'next-build': ['<version>'],
  'last-upload': [],
  'wait-build': ['<version>', '<build>'],
  'test-notes': ['<version>', '<build>', '<file>'],
  groups: [],
  distribute: ['<version>', '<build>', '<group>'],
  status: ['<version>', '[--json]'],
  version: ['<version>'],
  'whats-new': ['<version>'],
  attach: ['<version>', '[build]'],
  submit: ['<version>'],
  'review-attachment': ['<version>', '<file>'],
  validate: [],
  notes: ['<version>'],
  body: ['<version>', '[build]'],
  'what-to-test': ['[since]'],
  'marketing-version': ['[file]'],
}

export const usage = () =>
  'usage: asc.mjs ' + Object.entries(USAGE).map(([c, a]) => [c, ...a].join(' ')).join(' | ')

/// Checks a command line before anything touches the network.
export function parseArgs([command, ...args]) {
  const spec = Object.hasOwn(USAGE, command) ? USAGE[command] : undefined
  const required = spec?.filter((a) => a.startsWith('<')).length
  if (!spec || args.length < required || args.length > spec.length) throw new Error(usage())
  spec.forEach((name, i) => {
    const value = args[i]
    if (value === undefined) return
    if (/version/.test(name) && !VERSION.test(value)) throw new Error(`not a marketing version: ${value} (expected 1.2 or 1.2.3)`)
    if (/build/.test(name) && !BUILD.test(value)) throw new Error(`not a build number: ${value}`)
    if (name === '[n]' && !/^[1-9]\d*$/.test(value)) throw new Error(`not a count: ${value}`)
    if (name === '[--json]' && value !== '--json') throw new Error(usage())
    if (name === '[since]' && Number.isNaN(Date.parse(value))) throw new Error(`not a date: ${value}`)
  })
  return { command, args }
}

// MARK: pure helpers

/// MARKETING_VERSION from project.yml text, or '' when there is none.
export const marketingVersion = (yaml) =>
  yaml.match(/^\s*MARKETING_VERSION:\s*["']?([^"'\s#]+)["']?\s*(#.*)?$/m)?.[1] ?? ''

/// Compares dotted numbers (1.2 < 1.10, 9 < 10) part by part.
export function compareDotted(a, b) {
  const x = a.split('.').map(Number)
  const y = b.split('.').map(Number)
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0)
    if (d) return d
  }
  return 0
}

/// One more than the highest build App Store Connect has for a version, as a whole number; 1 when
/// there are none. A dotted build (an older date-time scheme such as 20260923.1530) counts by its
/// first part, so the next integer still sorts above it.
export function nextBuild(builds) {
  return Math.max(0, ...builds.map((b) => Number.parseInt(b.build, 10) || 0)) + 1
}

/// Flattens a builds response (include=preReleaseVersion,betaAppReviewSubmission) into rows,
/// newest version first, then newest build. `review` is empty for a build never sent to Beta App Review.
export function buildRows({ data, included = [] }) {
  const byId = (type, attribute) => Object.fromEntries(
    included.filter((i) => i.type === type).map((i) => [i.id, i.attributes[attribute]]))
  const marketing = byId('preReleaseVersions', 'version')
  const review = byId('betaAppReviewSubmissions', 'betaReviewState')
  return data
    .map((b) => ({
      id: b.id,
      build: b.attributes.version,
      version: marketing[b.relationships?.preReleaseVersion?.data?.id] ?? '',
      state: b.attributes.processingState,
      review: review[b.relationships?.betaAppReviewSubmission?.data?.id] ?? '',
      uploaded: b.attributes.uploadedDate ?? '',
    }))
    .sort((a, b) => compareDotted(b.version || '0', a.version || '0') || compareDotted(b.build, a.build))
}

/// The upload instant of the newest build in a listing, or ''.
export const latestUpload = (rows) => rows.map((r) => r.uploaded).filter(Boolean).sort().at(-1) ?? ''

/// status's line for a person.
export function statusLine(marketing, { state, build }) {
  if (!state) return `${marketing}: no iOS App Store version yet`
  return `${marketing}: ${state}, build ${build ?? 'none attached'}`
}

/// An internal group with automatic distribution gets every build on its own, and App Store
/// Connect refuses to add a build to it by hand.
export const automatic = (group) => Boolean(group.attributes.isInternalGroup && group.attributes.hasAccessToAllBuilds)

// Beta App Review Information fields, as App Store Connect labels them under TestFlight, then Test Information.
const CONTACT = { contactFirstName: 'First name', contactLastName: 'Last name', contactPhone: 'Phone number', contactEmail: 'Email' }
const SIGN_IN = { demoAccountName: 'User name', demoAccountPassword: 'Password' }

/// The labels of empty Beta App Review Information fields. Sign-in counts only when it is required.
export function missingReviewInfo(attributes) {
  const fields = { ...CONTACT, ...(attributes.demoAccountRequired ? SIGN_IN : {}) }
  return Object.entries(fields).filter(([key]) => !attributes[key]?.trim()).map(([, label]) => label)
}

// MARK: release notes

/// App Store Connect's cap on What's New and on TestFlight's What to Test, in characters.
export const NOTES_LIMIT = 4000
/// What fits on one row of the in-app card. Over these the row wraps, so it is a warning.
export const CARD_TITLE_LIMIT = 32
export const CARD_BODY_LIMIT = 90
const HEADERS = ['#New', '#Improved', '#Fixed']
/// A first version has no What's New field, so its block may be a plain paragraph kept as a record.
export const isFirstVersion = (version) => /^1\.0(\.0)?$/.test(version)

/// Every `## ` section of the notes file in file order, with its labelled fenced blocks. Lenient:
/// it reports what is there, and validateNotes decides what is wrong with it.
export function sections(markdown) {
  const found = []
  let section = null
  let label = null // the open fence's label, or null outside a fence
  let lines = []
  for (const line of markdown.replace(/\r/g, '').split('\n')) {
    if (label !== null) {
      if (line.trimEnd() === '```') {
        // A repeated label keeps the first block, so a stray second one cannot replace the text.
        if (section && !(label in section.blocks)) section.blocks[label] = lines.join('\n')
        label = null
      } else {
        lines.push(line)
      }
    } else if (line.startsWith('```')) {
      label = line.slice(3).trim()
      lines = []
    } else if (line.startsWith('##')) {
      section = { heading: line, version: line.slice(2).trim(), blocks: {} }
      found.push(section)
    }
  }
  return found
}

/// The problems with one `whatsnew` block (the in-app card). Under any header but `#Fixed`, a row
/// is `- <icon> | <title> | <body>`. `icons` is a list of allowed icon names, or true for any word.
function whatsNewErrors(version, text, icons) {
  const errors = []
  let header = ''
  for (const line of text.split('\n').map((l) => l.trim())) {
    if (line.startsWith('#')) {
      header = line
      if (!HEADERS.includes(line)) errors.push(`${version}: whatsnew header "${line}" is not one of ${HEADERS.join(', ')}`)
    } else if (line.startsWith('-') && header !== '#Fixed') {
      const [icon, title] = line.slice(1).split('|').map((p) => p.trim())
      const known = Array.isArray(icons) ? icons.includes(icon) : /^[a-z][a-z0-9-]*$/.test(icon)
      if (!known) errors.push(`${version}: unknown icon "${icon}" in "${line}"${Array.isArray(icons) ? ` (one of ${icons.join(', ')})` : ''}`)
      if (!title) errors.push(`${version}: no title in "${line}"`)
    }
  }
  return errors
}

/// The newest section's `whatsnew` rows whose title or body is over the card's limits.
export function cardWarnings(markdown) {
  const [newest] = sections(markdown)
  const warnings = []
  for (const line of (newest?.blocks.whatsnew ?? '').split('\n').map((l) => l.trim())) {
    const [, title = '', body = ''] = line.split('|').map((p) => [...p.trim()].length)
    if (title > CARD_TITLE_LIMIT || body > CARD_BODY_LIMIT) {
      warnings.push(`${newest.version}: card row is over ${CARD_TITLE_LIMIT} (title ${title}) or ${CARD_BODY_LIMIT} (body ${body}) characters: "${line}"`)
    }
  }
  return warnings
}

/// Everything wrong with the notes file, as readable strings. Empty means it is fine. A file with
/// no sections yet is fine. `whatsNew` is appstore.json's value: false, true, or a list of icons.
/// Only the newest section must have a `whatsnew` block, so a repo can turn it on mid-life.
export function validateNotes(markdown, { whatsNew = false } = {}) {
  const errors = []
  const seen = new Set()
  let previous = null
  for (const { heading, version, blocks } of sections(markdown)) {
    if (!heading.startsWith('## ') || !VERSION.test(version)) {
      errors.push(`malformed heading "${heading}": expected "## <major>.<minor>[.<patch>]"`)
      continue
    }
    if (seen.has(version)) errors.push(`${version}: more than one section`)
    else if (previous && compareDotted(version, previous) >= 0) errors.push(`${version}: below ${previous}, but the file is newest first`)
    seen.add(version)
    previous = version

    const text = blocks.appstore
    if (text === undefined) errors.push(`${version}: no \`appstore\` block`)
    else if (!text.trim()) errors.push(`${version}: the \`appstore\` block is empty`)
    else {
      const length = [...text].length
      if (length > NOTES_LIMIT) errors.push(`${version}: the \`appstore\` block is ${length} characters; App Store Connect allows ${NOTES_LIMIT}`)
      if (!isFirstVersion(version) && !HEADERS.includes(text.split('\n')[0].trim())) {
        errors.push(`${version}: the \`appstore\` block must start with one of ${HEADERS.join(', ')}`)
      }
      for (const line of text.split('\n')) {
        if (line.startsWith('#') && !HEADERS.includes(line.trim())) errors.push(`${version}: "${line}" is not one of ${HEADERS.join(', ')}`)
      }
      // App Store Connect shows the version number beside the text.
      if (new RegExp(`(?<![\\d.])${version.replace(/\./g, '\\.')}(?!\\.?\\d)`).test(text)) {
        errors.push(`${version}: the \`appstore\` block repeats the version number; App Store Connect already shows it`)
      }
    }
    if (whatsNew) {
      if (blocks.whatsnew === undefined) {
        if (seen.size === 1) errors.push(`${version}: no \`whatsnew\` block`)
      }
      else if (!blocks.whatsnew.trim()) errors.push(`${version}: the \`whatsnew\` block is empty`)
      else errors.push(...whatsNewErrors(version, blocks.whatsnew, whatsNew))
    }
  }
  return errors
}

/// The `appstore` block for `version`, exactly as written. Throws rather than return text from a
/// section that would not pass validateNotes, because this is what goes to App Store Connect.
export function appStoreNotes(markdown, version, options) {
  const mine = validateNotes(markdown, options).filter((e) => e.startsWith(`${version}:`))
  if (mine.length) throw new Error(mine.join('\n'))
  const section = sections(markdown).find((s) => s.version === version)
  if (!section) throw new Error(`${version}: no section in the release notes. Add one in the version PR (/kguydev:appstore step A).`)
  return section.blocks.appstore
}

/// The GitHub Release body: `#New` becomes `### New`, the bullets are already Markdown, and with a
/// build the last line is `Build: <build>`, which publish-release.yml reads back.
// ponytail: the store text is not escaped for Markdown. Escape `*`, `_` and `<` if a note needs them literally.
export function releaseBody(markdown, version, build, options) {
  const body = appStoreNotes(markdown, version, options).replace(/^#\s*(\S.*)$/gm, '### $1').trim()
  return build ? `${body}\n\nBuild: ${build}\n` : `${body}\n`
}

// MARK: What to Test

/// The `## What to test` bullets of a PR body. The template's HTML comments, empty `-` bullet
/// and old `<...>` placeholder do not count.
export function prBullets(body) {
  const section = (body ?? '').replace(/\r/g, '').match(/^## What to test[ \t]*\n([\s\S]*?)(?=^## |(?![\s\S]))/m)
  if (!section) return []
  return section[1].replace(/<!--[\s\S]*?-->/g, '').split('\n').map((l) => l.trim())
    .filter((l) => /^[-*]/.test(l))
    .map((l) => l.replace(/^[-*\s]+/, '').trim())
    .filter((t) => t && !t.startsWith('<'))
}

// App Store Connect refuses checkbox glyphs in What to Test with a 409 after the upload.
const GLYPHS = [['☐', 'box'], ['☑', 'checked box'], ['☒', 'checked box'], ['✓', 'check'], ['✔', 'check']]

/// TestFlight's What to Test from `gh pr list --json number,title,body,labels,mergedAt,files`: for each
/// PR merged after `since`, newest first, its title over its What to test bullets as `- text`. PRs
/// labelled `internal` are left out, and so are PRs whose files all sit outside `appDir`. It fits the
/// limit by dropping whole PRs from the oldest end, and says "Small fixes and polish." when nothing is left.
export function whatToTest(prs, { since, appDir } = {}) {
  const cutoff = since ? Date.parse(since) : -Infinity
  const inApp = (pr) => !appDir || !pr.files?.length || pr.files.some((f) => f.path.startsWith(`${appDir.replace(/\/$/, '')}/`))
  const notes = prs
    // Apple stamps uploads to the second; a PR merged at or before it is in that build.
    .filter((pr) => Date.parse(pr.mergedAt) > cutoff)
    .filter((pr) => !pr.labels?.some((l) => l.name === 'internal') && inApp(pr))
    .sort((a, b) => Date.parse(b.mergedAt) - Date.parse(a.mergedAt))
    .map((pr) => GLYPHS.reduce((text, [glyph, word]) => text.replaceAll(glyph, word),
      [pr.title, ...prBullets(pr.body).map((t) => `- ${t}`)].join('\n')))
  if (!notes.length) return 'Small fixes and polish.'
  const length = (parts) => [...parts.join('\n\n')].length
  const kept = [...notes]
  while (kept.length > 1 && length(kept) > NOTES_LIMIT) kept.pop()
  // A single PR longer than the limit is the one case that gets cut.
  let text = [...kept.join('\n\n')].slice(0, NOTES_LIMIT).join('')
  const more = '\n\n(and earlier changes)'
  if (kept.length < notes.length && [...text + more].length <= NOTES_LIMIT) text += more
  return text
}

/// The requests Apple's uploadOperations ask for, each with its slice of the file.
export const uploadParts = (operations, bytes) => operations.map((op) => ({
  method: op.method,
  url: op.url,
  headers: Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value])),
  body: bytes.subarray(op.offset, op.offset + op.length),
}))

// MARK: network

const base64url = (value) => Buffer.from(value).toString('base64url')

/// An App Store Connect token, valid 20 minutes (Apple's maximum). `ieee-p1363` matters: Node signs
/// ECDSA as DER by default, a JWT wants the raw r||s pair, and Apple answers the DER one with a bare 401.
export function jwt({ keyId, issuerId, privateKey, now = Date.now() }) {
  const iat = Math.floor(now / 1000)
  const head = base64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))
  const claims = base64url(JSON.stringify({ iss: issuerId, iat, exp: iat + 20 * 60, aud: 'appstoreconnect-v1' }))
  const signature = sign('sha256', Buffer.from(`${head}.${claims}`), { key: privateKey, dsaEncoding: 'ieee-p1363' })
  return `${head}.${claims}.${base64url(signature)}`
}

let token
function auth(env = process.env) {
  if (token) return token
  const { ASC_KEY_ID: keyId, ASC_ISSUER_ID: issuerId, ASC_KEY_P8_BASE64: p8 } = env
  if (!keyId || !issuerId || !p8) throw new Error('ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 must be set (run it as scripts/asc <command>)')
  token = jwt({ keyId, issuerId, privateKey: Buffer.from(p8, 'base64').toString('utf8') })
  return token
}

async function asc(path, { method = 'GET', body } = {}) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${auth()}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  })
  if (!response.ok) {
    const text = await response.text()
    let detail = text
    try {
      detail = JSON.parse(text).errors.map((e) => `${e.code}: ${e.detail ?? e.title}`).join('\n')
    } catch {}
    throw Object.assign(new Error(`App Store Connect ${response.status} on ${method} ${path.split('?')[0]}\n${detail}`), { status: response.status })
  }
  return response.status === 204 ? null : response.json()
}

let app
async function findApp() {
  if (app) return app
  const { bundleId } = config()
  const { data } = await asc(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`)
  app = data.find((a) => a.attributes.bundleId === bundleId)
  if (!app) throw new Error(`no app with bundle id ${bundleId} in App Store Connect`)
  return app
}

async function listBuilds(limit, { version, build } = {}) {
  const { id } = await findApp()
  let query = `filter[app]=${id}&sort=-uploadedDate&include=preReleaseVersion,betaAppReviewSubmission&limit=${limit}`
  if (version) query += `&filter[preReleaseVersion.version]=${encodeURIComponent(version)}`
  if (build) query += `&filter[version]=${encodeURIComponent(build)}`
  return buildRows(await asc(`/v1/builds?${query}`))
}

/// A build number is unique only within its marketing version, so a build is always looked up in one.
const findBuild = async (version, build) => (await listBuilds(1, { version, build }))[0]

/// Waits up to 30 minutes for a build to appear and finish processing.
async function processedBuild(version, build) {
  for (let i = 0; i < 60; i++) {
    const row = await findBuild(version, build)
    if (row?.state === 'VALID') return row
    if (row && row.state !== 'PROCESSING') throw new Error(`${version} (${build}): ${row.state}. Apple refused the binary while processing it; App Store Connect emails the reason.`)
    await sleep(30_000)
  }
  throw new Error(`${version} (${build}): not processed after 30 minutes`)
}

async function findVersion(marketing) {
  const { id } = await findApp()
  const { data } = await asc(`/v1/apps/${id}/appStoreVersions?filter[versionString]=${encodeURIComponent(marketing)}&filter[platform]=IOS`)
  return data[0]
}

async function requireVersion(marketing) {
  const found = await findVersion(marketing)
  if (!found) throw new Error(`${marketing} has no iOS App Store version in App Store Connect yet. Prepare Release creates it.`)
  return found
}

/// The en-US localization of the App Store version, which holds What's New.
async function enLocalization(marketing) {
  const { id } = await requireVersion(marketing)
  const { data } = await asc(`/v1/appStoreVersions/${id}/appStoreVersionLocalizations?limit=200`)
  const en = data.find((l) => l.attributes.locale === 'en-US')
  if (!en) throw new Error(`${marketing} has no en-US localization in App Store Connect`)
  return en
}

/// Apple's 403 and 409 on an edit to the version, said so a person knows what to do.
function refusal(error, marketing, what) {
  if (error.status === 403) {
    return new Error(`App Store Connect refused to edit ${marketing}'s ${what} (403): the API key's role cannot change App Store metadata. `
      + 'It needs App Manager or Admin. Make a key with that role in App Store Connect, under Users and Access, then Integrations, '
      + `and replace ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8_BASE64 in the 1Password Environment.\n${error.message}`)
  }
  if (error.status === 409) {
    return new Error(`App Store Connect refused to edit ${marketing}'s ${what} (409). Usually the version is no longer editable: `
      + `it is submitted, in review, or live. Apple's reason:\n${error.message}`)
  }
  return error
}

// RELEASE_NOTES=<path> reads another copy, such as origin/main's.
const readNotes = () => readFileSync(process.env.RELEASE_NOTES || repoPath(config().notesFile), 'utf8')
const notesOptions = () => ({ whatsNew: config().whatsNew })

// MARK: commands

// Beta App Review states that need no new submission. REJECTED is left out so a rerun tries again.
const SUBMITTED = ['WAITING_FOR_REVIEW', 'IN_REVIEW', 'APPROVED']

/// Submits a build for Beta App Review once. A second external group, or a rerun, finds the first
/// submission and skips.
async function betaReview(appId, build, buildId) {
  const { data } = await asc(`/v1/betaAppReviewSubmissions?filter[build]=${buildId}`)
  const state = data[0]?.attributes.betaReviewState
  if (SUBMITTED.includes(state)) return console.log(`build ${build}: already submitted, Beta App Review ${state}`)
  try {
    const { data: submission } = await asc('/v1/betaAppReviewSubmissions', {
      method: 'POST',
      body: { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: buildId } } } } },
    })
    console.log(`build ${build}: submitted, Beta App Review ${submission.attributes?.betaReviewState ?? 'WAITING_FOR_REVIEW'}`)
  } catch (error) {
    // Apple's refusal does not reliably name the missing fields, so read them.
    const detail = await asc(`/v1/apps/${appId}/betaAppReviewDetail`).catch(() => null)
    const missing = detail ? missingReviewInfo(detail.data.attributes) : []
    if (!missing.length) throw error
    throw new Error(`build ${build}: Beta App Review refused. Beta App Review Information is missing ${missing.join(', ')}. `
      + `Fill it in App Store Connect under TestFlight, then Test Information, and rerun.\n${error.message}`)
  }
}

export const commands = {
  async builds(n = '10', version) {
    for (const r of await listBuilds(Number(n), { version })) {
      console.log(`${r.build}\t${r.version}\t${r.state}\t${r.review || '-'}\t${r.uploaded}`)
    }
  },

  // release.yml archives with this, so a build from a Mac and one from CI never collide.
  async 'next-build'(version) {
    console.log(nextBuild(await listBuilds(200, { version })))
  },

  // release.yml scopes a build's What to Test to PRs merged after this.
  async 'last-upload'() {
    console.log(latestUpload(await listBuilds(1)))
  },

  async 'wait-build'(version, build) {
    const row = await processedBuild(version, build)
    console.log(`${version} (${build}): ${row.state}`)
  },

  // pilot's --changelog is applied by its distribution step, which --skip_submission skips,
  // so release.yml sets What to Test here.
  async 'test-notes'(version, build, file) {
    const whatsNew = readFileSync(file, 'utf8').trim()
    if (!whatsNew) throw new Error(`${file} is empty`)
    const length = [...whatsNew].length
    if (length > NOTES_LIMIT) throw new Error(`${file} is ${length} characters; TestFlight allows ${NOTES_LIMIT}`)
    const row = await processedBuild(version, build)
    const { data } = await asc(`/v1/builds/${row.id}/betaBuildLocalizations`)
    const existing = data.find((l) => l.attributes.locale === 'en-US')
    if (existing) {
      await asc(`/v1/betaBuildLocalizations/${existing.id}`, {
        method: 'PATCH',
        body: { data: { type: 'betaBuildLocalizations', id: existing.id, attributes: { whatsNew } } },
      })
    } else {
      await asc('/v1/betaBuildLocalizations', {
        method: 'POST',
        body: {
          data: {
            type: 'betaBuildLocalizations',
            attributes: { locale: 'en-US', whatsNew },
            relationships: { build: { data: { type: 'builds', id: row.id } } },
          },
        },
      })
    }
    console.log(`build ${build}: What to Test set, ${length} characters`)
  },

  async groups() {
    const { id } = await findApp()
    const { data } = await asc(`/v1/betaGroups?filter[app]=${id}&limit=200`)
    for (const g of data) {
      const kind = g.attributes.isInternalGroup ? 'internal' : 'external'
      console.log(`${g.attributes.name}\t${g.id}\t${kind}${automatic(g) ? '\tautomatic' : ''}`)
    }
  },

  async distribute(version, build, groupName) {
    const name = groupName.trim()
    const { id } = await findApp()
    const row = await findBuild(version, build)
    if (!row) throw new Error(`${version} (${build}): not in App Store Connect`)
    if (row.state !== 'VALID') throw new Error(`${version} (${build}): ${row.state}, not processed yet`)
    const { data } = await asc(`/v1/betaGroups?filter[app]=${id}&filter[name]=${encodeURIComponent(name)}&limit=200`)
    const group = data.find((g) => g.attributes.name === name)
    if (!group) throw new Error(`no TestFlight group named "${name}"; \`asc.mjs groups\` lists them`)
    const skip = `${name} is an internal group with automatic distribution; build ${build} reaches it without being added`
    if (automatic(group)) return console.log(skip)
    try {
      await asc(`/v1/betaGroups/${group.id}/relationships/builds`, { method: 'POST', body: { data: [{ type: 'builds', id: row.id }] } })
    } catch (error) {
      // The group's attributes can lag its settings; Apple's refusal says the same thing.
      if (error.status === 422 && error.message.includes('Cannot add internal group')) return console.log(skip)
      throw error
    }
    console.log(`build ${build} added to ${name}`)
    // Adding a build to an external group does not submit it; testers get it only after review.
    if (!group.attributes.isInternalGroup) await betaReview(id, build, row.id)
  },

  // publish-release.yml publishes only at READY_FOR_DISTRIBUTION, and takes the build from here.
  async status(marketing, json) {
    const version = await findVersion(marketing)
    const build = version && (await asc(`/v1/appStoreVersions/${version.id}/build`)).data
    const status = { state: version?.attributes.appVersionState ?? null, build: build?.attributes.version ?? null }
    console.log(json ? JSON.stringify(status) : statusLine(marketing, status))
  },

  async version(marketing) {
    let found = await findVersion(marketing)
    if (!found) {
      const { id } = await findApp()
      ;({ data: found } = await asc('/v1/appStoreVersions', {
        method: 'POST',
        body: {
          data: {
            type: 'appStoreVersions',
            // Manual release: approval parks the version until Kurtis presses Release.
            attributes: { platform: 'IOS', versionString: marketing, releaseType: 'MANUAL' },
            relationships: { app: { data: { type: 'apps', id } } },
          },
        },
      }))
      console.log(`${marketing}: created, manual release`)
    }
    console.log(`${marketing}: ${found.attributes.appVersionState}`)
  },

  async 'whats-new'(marketing) {
    if (isFirstVersion(marketing)) return console.log(`${marketing}: the first version has no What's New in App Store Connect. Nothing was sent.`)
    const whatsNew = appStoreNotes(readNotes(), marketing, notesOptions())
    const en = await enLocalization(marketing)
    try {
      await asc(`/v1/appStoreVersionLocalizations/${en.id}`, {
        method: 'PATCH',
        body: { data: { type: 'appStoreVersionLocalizations', id: en.id, attributes: { whatsNew } } },
      })
    } catch (error) {
      throw refusal(error, marketing, "What's New")
    }
    console.log(`${marketing}: What's New updated, ${[...whatsNew].length} characters`)
  },

  async attach(marketing, build) {
    const { id } = await requireVersion(marketing)
    const row = build ? await findBuild(marketing, build) : (await listBuilds(50, { version: marketing })).find((r) => r.state === 'VALID')
    if (!row) throw new Error(build ? `${marketing} (${build}): not in App Store Connect` : `${marketing}: no processed build of this version`)
    if (row.state !== 'VALID') throw new Error(`${marketing} (${row.build}): ${row.state}, not processed yet`)
    try {
      await asc(`/v1/appStoreVersions/${id}/relationships/build`, { method: 'PATCH', body: { data: { type: 'builds', id: row.id } } })
    } catch (error) {
      throw refusal(error, marketing, 'build')
    }
    console.log(`${marketing}: build ${row.build} attached`)
  },

  // reviewSubmissions replaced appStoreVersionSubmissions: open (or reuse) the app's draft
  // submission, put the version in it, then mark it submitted. A rerun after a partial failure
  // picks up the same draft.
  async submit(marketing) {
    const { id: appId } = await findApp()
    const { id } = await requireVersion(marketing)
    const { data } = await asc(`/v1/reviewSubmissions?filter[app]=${appId}&filter[platform]=IOS`
      + '&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES&include=appStoreVersionForReview')
    let submission = data[0]
    if (!submission) {
      ;({ data: submission } = await asc('/v1/reviewSubmissions', {
        method: 'POST',
        body: { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: appId } } } } },
      }))
    }
    try {
      if (submission.relationships?.appStoreVersionForReview?.data?.id !== id) {
        await asc('/v1/reviewSubmissionItems', {
          method: 'POST',
          body: {
            data: {
              type: 'reviewSubmissionItems',
              relationships: {
                reviewSubmission: { data: { type: 'reviewSubmissions', id: submission.id } },
                appStoreVersion: { data: { type: 'appStoreVersions', id } },
              },
            },
          },
        })
      }
      const { data: sent } = await asc(`/v1/reviewSubmissions/${submission.id}`, {
        method: 'PATCH',
        body: { data: { type: 'reviewSubmissions', id: submission.id, attributes: { submitted: true } } },
      })
      console.log(`${marketing}: submitted for review (${sent.attributes.state})`)
    } catch (error) {
      throw refusal(error, marketing, 'review submission')
    }
  },

  // Prepare Release sends the App Review sign-in QR here, so nobody re-adds it by hand each version.
  async 'review-attachment'(marketing, file) {
    const bytes = readFileSync(file)
    const fileName = basename(file)
    const { id } = await requireVersion(marketing)
    try {
      let detail = (await asc(`/v1/appStoreVersions/${id}/appStoreReviewDetail`).catch((e) => {
        if (e.status === 404) return { data: null }
        throw e
      })).data
      if (!detail) {
        ;({ data: detail } = await asc('/v1/appStoreReviewDetails', {
          method: 'POST',
          body: { data: { type: 'appStoreReviewDetails', relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id } } } } },
        }))
      }
      const { data: existing } = await asc(`/v1/appStoreReviewDetails/${detail.id}/appStoreReviewAttachments?limit=200`)
      for (const old of existing.filter((a) => a.attributes.fileName === fileName)) {
        await asc(`/v1/appStoreReviewAttachments/${old.id}`, { method: 'DELETE' })
        console.log(`${marketing}: removed the old ${fileName}`)
      }
      const { data: reserved } = await asc('/v1/appStoreReviewAttachments', {
        method: 'POST',
        body: {
          data: {
            type: 'appStoreReviewAttachments',
            attributes: { fileName, fileSize: bytes.length },
            relationships: { appStoreReviewDetail: { data: { type: 'appStoreReviewDetails', id: detail.id } } },
          },
        },
      })
      for (const part of uploadParts(reserved.attributes.uploadOperations, bytes)) {
        const response = await fetch(part.url, { method: part.method, headers: part.headers, body: part.body })
        if (!response.ok) throw new Error(`upload of ${fileName} failed: ${response.status} ${await response.text()}`)
      }
      await asc(`/v1/appStoreReviewAttachments/${reserved.id}`, {
        method: 'PATCH',
        body: {
          data: {
            type: 'appStoreReviewAttachments',
            id: reserved.id,
            attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') },
          },
        },
      })
      // Apple processes the file after the commit; a stuck or failed one blocks the submission.
      for (let i = 0; i < 12; i++) {
        const { data } = await asc(`/v1/appStoreReviewAttachments/${reserved.id}`)
        const state = data.attributes.assetDeliveryState?.state
        if (state === 'COMPLETE') return console.log(`${marketing}: review attachment ${fileName} uploaded`)
        if (state === 'FAILED') throw new Error(`${marketing}: Apple could not process ${fileName}: ${JSON.stringify(data.attributes.assetDeliveryState.errors ?? [])}`)
        await sleep(5_000)
      }
      console.log(`${marketing}: review attachment ${fileName} uploaded, still processing`)
    } catch (error) {
      throw refusal(error, marketing, 'review attachment')
    }
  },

  async validate() {
    const markdown = readNotes()
    const errors = validateNotes(markdown, notesOptions())
    if (errors.length) throw new Error(errors.map((e) => `${config().notesFile}: ${e}`).join('\n'))
    for (const warning of cardWarnings(markdown)) console.log(`warning: ${config().notesFile}: ${warning}`)
    console.log(`${config().notesFile}: ${sections(markdown).length} sections, all valid`)
  },

  async notes(marketing) {
    process.stdout.write(appStoreNotes(readNotes(), marketing, notesOptions()))
  },

  async body(marketing, build) {
    process.stdout.write(releaseBody(readNotes(), marketing, build, notesOptions()))
  },

  async 'what-to-test'(since) {
    console.log(whatToTest(JSON.parse(readFileSync(0, 'utf8')), { since, appDir: config().appDir }))
  },

  async 'marketing-version'(file = repoPath(config().projectYml)) {
    const version = marketingVersion(readFileSync(file === '-' ? 0 : file, 'utf8'))
    if (!version) throw new Error(`no MARKETING_VERSION in ${file === '-' ? 'stdin' : file}`)
    console.log(version)
  },
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { command, args } = parseArgs(process.argv.slice(2))
    await commands[command](...args)
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}
