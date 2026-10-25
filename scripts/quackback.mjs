#!/usr/bin/env node
// Keeps request statuses on Quackback (feedback.babybuddy.app) in step with GitHub. An issue or PR
// belongs to a request when its body has a line `Quackback: post_<id>`, one line per request.
//
//   node scripts/quackback.mjs issue <event.json>          an `issues` event: Planned or Complete
//   node scripts/quackback.mjs ship <version> <published>  the changelog entry, then Shipped
//   node scripts/quackback.mjs open-issue <request>... [--to <issue>] [--milestone <version>]
//     [--title "<text>"] [--dry-run]                      a feature-request issue naming them
//
// A request is a post ID, its admin URL (`?post=post_…`) or its public URL (`/b/<board>/posts/post_…`).
// `open-issue` creates the issue with the local `gh` login, so the status workflow trusts it, and
// takes the key from the login keychain (`babybuddy-quackback-api-key`) when QUACKBACK_API_KEY is
// unset. `--to` appends to an existing issue instead. It stops if any issue already names a request.
//
// `ship` reads issue and PR bodies on stdin and the notes from Docs/release-notes.md (or
// `RELEASE_NOTES=<path>`). `<published>` is an ISO 8601 time, the GitHub Release's publishedAt.
//
// QUACKBACK_API_KEY is an admin API key. QUACKBACK_URL overrides the API base. QUACKBACK_DRY_RUN=1
// still reads from Quackback, so an unknown post still fails, but prints each write instead of
// sending it.
//
// No dependencies, on purpose, like release.mjs.

import { execFileSync } from 'node:child_process'
import { appendFileSync, readFileSync } from 'node:fs'
import { userInfo } from 'node:os'
import { fileURLToPath } from 'node:url'
import { appStoreNotes } from './release.mjs'

const API = process.env.QUACKBACK_URL ?? 'https://feedback.babybuddy.app/api/v1'
const DRY_RUN = process.env.QUACKBACK_DRY_RUN === '1'
const SITE = new URL(API).origin
const LABEL = 'feature-request'

/// The post IDs named by `Quackback:` lines, in order, each once. Anything after `post_` is taken
/// as written, so a mistyped ID reaches Quackback and fails there instead of being skipped.
export function postIds(body) {
  const found = [...(body ?? '').matchAll(/^[ \t]*Quackback:[ \t]*(post_\w+)[ \t]*\r?$/gim)]
  return [...new Set(found.map((m) => m[1]))]
}

/// What an `issues` event asks for: the status to set, by name, and the posts to set it on.
/// `status` is null when the posts should be left alone. An edit acts only on IDs it added; any
/// other action acts on every ID in the body.
export function plan({ action, issue, changes }) {
  let ids = postIds(issue.body)
  if (action === 'edited') {
    const before = new Set(postIds(changes?.body?.from ?? issue.body))
    ids = ids.filter((id) => !before.has(id))
  } else if (!['opened', 'closed', 'reopened'].includes(action)) {
    ids = []
  }
  // Closed as not planned (or as a duplicate) leaves the request to a person.
  const status = issue.state === 'open' ? 'Planned' : issue.state_reason === 'completed' ? 'Complete' : null
  return { ids, status }
}

/// Whether a post at `current` moves to `target`. Nothing moves a post back from Shipped.
export const moves = (current, target) => current !== target && current !== 'Shipped'

/// The changelog entry for a release: the `appstore` block, with its `#New` labels as headings.
/// Publish Release finds an earlier run's entry by this title, so changing it duplicates entries.
export function changelogEntry(version, notes) {
  return { title: `Version ${version}`, content: notes.replace(/^#\s*(\S.*)$/gm, '## $1').trim() }
}

// MARK: open-issue, the pure part

/// The post ID in a bare `post_…`, an admin URL's `post=` value, or a public `/posts/post_…` URL.
export function requestId(input) {
  if (/^post_[0-9a-z]+$/i.test(input)) return input
  let url
  try { url = new URL(input) } catch { fail(`"${input}" is not a post ID or a Quackback URL`) }
  const id = url.searchParams.get('post') ?? url.pathname.match(/\/posts\/(post_[0-9a-z]+)\/?$/i)?.[1]
  if (!id || !/^post_[0-9a-z]+$/i.test(id)) fail(`"${input}" names no post`)
  return id
}

export function openIssueArgs(argv) {
  const args = { ids: [], to: null, milestone: null, title: null, dryRun: false }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--dry-run') args.dryRun = true
    else if (['--to', '--milestone', '--title'].includes(arg)) {
      if (argv[i + 1] === undefined) fail(`${arg} needs a value`)
      args[arg.slice(2)] = argv[++i]
    } else if (arg.startsWith('--')) fail(`unknown option ${arg}`)
    else args.ids.push(requestId(arg))
  }
  args.ids = [...new Set(args.ids)]
  if (args.ids.length === 0) fail('name at least one request')
  return args
}

/// A stranger's text made inert: `@name` can't notify anyone and `Quackback:` can't name a post.
/// A zero-width joiner splits each, so the text still reads the same.
export const inert = (text) => (text ?? '')
  .replace(/@(?=[\w-])/g, '@\u200D')
  .replace(/(quack)(back)/gi, '$1\u200D$2')

// Every line break JavaScript's `^` honours, not only \n, so no stranger's line goes unquoted.
const LINES = /\r\n|[\n\r\u2028\u2029]/
const oneLine = (text) => inert(text).split(LINES).join(' ').trim()

/// One request's section: its title, its text quoted, its votes, board and tags, and its public
/// link. Never the requester's name or email.
export function section(post) {
  const quoted = inert(post.content?.trim() || '(no text)').split(LINES).map((l) => `> ${l}`.trimEnd()).join('\n')
  const tags = (post.tags ?? []).map((t) => oneLine(t.name)).filter(Boolean)
  const facts = [`${post.voteCount ?? 0} vote${post.voteCount === 1 ? '' : 's'}`, `board: ${oneLine(post.boardName) || 'none'}`]
  if (tags.length) facts.push(`tags: ${tags.join(', ')}`)
  return `### ${oneLine(post.title)}\n\n${quoted}\n\n${facts.join(' · ')}\n` +
    `${SITE}/b/${encodeURIComponent(post.boardSlug ?? '')}/posts/${post.id}`
}

const quackbackLines = (ids) => ids.map((id) => `Quackback: ${id}`).join('\n')

export const issueBody = (posts) => `${posts.map(section).join('\n\n')}\n\n${quackbackLines(posts.map((p) => p.id))}\n`

/// An existing body with the new sections added, and every `Quackback:` line, old then new, at
/// the end.
export function appendedBody(body, posts) {
  const rest = (body ?? '').split(/\r?\n/).filter((line) => postIds(line).length === 0).join('\n').trimEnd()
  const ids = [...new Set([...postIds(body), ...posts.map((p) => p.id)])]
  return `${rest ? `${rest}\n\n` : ''}${posts.map(section).join('\n\n')}\n\n${quackbackLines(ids)}\n`
}

/// The post, or a failure if Quackback has deleted it: `GET /posts/<id>` still returns a deleted
/// post, with `deletedAt` set, and its public link is gone.
export function live(post) {
  if (post.deletedAt) fail(`${post.id}: deleted in Quackback on ${post.deletedAt.slice(0, 10)}. Nothing was written.`)
  return post
}

/// Each requested ID that one of `issues` already names, with that issue's URL.
export const duplicates = (ids, issues) => ids.flatMap((id) => {
  const issue = issues.find((i) => postIds(i.body).includes(id))
  return issue ? [{ id, url: issue.url }] : []
})

// MARK: Quackback

async function api(path, method = 'GET', body) {
  const key = process.env.QUACKBACK_API_KEY
  if (!key) throw new Error('QUACKBACK_API_KEY is not set')
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  })
  // Quackback's error bodies name the problem and carry no credential; the key is never printed.
  if (!response.ok) {
    throw Object.assign(new Error(`Quackback ${response.status} for ${method} ${path}\n${await response.text()}`),
      { status: response.status })
  }
  return response.json()
}

function write(path, method, body) {
  if (!DRY_RUN) return api(path, method, body)
  report(`dry run: would ${method} ${path} ${JSON.stringify(body)}`)
  return null
}

function report(line) {
  if (DRY_RUN && !line.startsWith('dry run')) line = `dry run: ${line}`
  console.log(line)
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${line}\n\n`)
}

/// The statuses by name, and each post with its status's name. Every post is read before anything
/// is written, so one unknown ID changes nothing.
async function load(ids) {
  const { data: statuses } = await api('/statuses')
  const named = (name) => statuses.find((s) => s.name.toLowerCase() === name.toLowerCase())?.id ??
    fail(`Quackback has no "${name}" status`)
  const names = new Map(statuses.map((s) => [s.id, s.name]))
  const posts = []
  for (const id of ids) {
    try {
      const { data: post } = await api(`/posts/${id}`)
      posts.push({ id, title: post.title, status: names.get(post.statusId) })
    } catch (error) {
      if (error.status === 404 || error.status === 400) fail(`${id}: Quackback has no such post. Check the "Quackback:" line.\n${error.message}`)
      throw error
    }
  }
  return { named, posts }
}

async function setStatus(posts, named, target) {
  const id = named(target)
  for (const post of posts) {
    if (!moves(post.status, target)) {
      report(`${post.id} "${post.title}" is ${post.status}; left as it is`)
      continue
    }
    await write(`/posts/${post.id}`, 'PATCH', { statusId: id })
    report(`${post.id} "${post.title}": ${post.status} → ${target}`)
  }
}

export async function issueEvent(event) {
  const { ids, status } = plan(event)
  if (ids.length === 0) return
  if (!status) {
    report(`#${event.issue.number} was closed as ${event.issue.state_reason?.replace('_', ' ') ?? 'not completed'}, so its requests were left alone. ` +
      `Decide in Quackback what each becomes: ${ids.join(', ')}`)
    return
  }
  const { named, posts } = await load(ids)
  await setStatus(posts, named, status)
}

/// All changelog entries, drafts included, across every page.
async function changelog() {
  const entries = []
  let cursor = ''
  for (;;) {
    const { data, meta } = await api(`/changelog?limit=100${cursor && `&cursor=${encodeURIComponent(cursor)}`}`)
    entries.push(...data)
    if (!meta?.pagination?.hasMore) return entries
    cursor = meta.pagination.cursor
  }
}

/// Posts the release's changelog entry once, links it to the posts, and sets them to Shipped.
/// A rerun finds the entry by title and only adds missing links, and a post already Shipped is
/// not set again, so nobody is notified twice.
export async function ship(version, publishedAt, ids, markdown) {
  if (Number.isNaN(Date.parse(publishedAt))) fail(`"${publishedAt}" is not a date`)
  const entry = changelogEntry(version, appStoreNotes(markdown, version))
  const { named, posts } = await load(ids)
  named('Shipped') // fail before posting anything if the status is missing

  const existing = (await changelog()).find((e) => e.title === entry.title)
  if (!existing) {
    const created = await write('/changelog', 'POST',
      { ...entry, publishedAt: new Date(publishedAt).toISOString(), linkedPostIds: ids })
    report(`changelog: posted "${entry.title}", dated ${publishedAt}, linked to ${ids.length} request(s)${created ? ` (${created.data.id})` : ''}`)
  } else {
    const linked = existing.linkedPosts.map((p) => p.id)
    const missing = ids.filter((id) => !linked.includes(id))
    if (missing.length) await write(`/changelog/${existing.id}`, 'PATCH', { linkedPostIds: [...linked, ...missing] })
    report(`changelog: "${entry.title}" is already there (${existing.id}); linked ${missing.length} more request(s)`)
  }
  if (ids.length === 0) report(`no issue or PR on the ${version} milestone names a Quackback request`)
  await setStatus(posts, named, 'Shipped')
}

// MARK: open-issue, the GitHub part

const gh = (args, input) => execFileSync('gh', args, { encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'inherit'] })

function loadApiKey() {
  if (process.env.QUACKBACK_API_KEY) return
  try {
    process.env.QUACKBACK_API_KEY = execFileSync('security',
      ['find-generic-password', '-a', userInfo().username, '-s', 'babybuddy-quackback-api-key', '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    fail('No Quackback API key. Set QUACKBACK_API_KEY, or add it to the login keychain with\n' +
      '  security add-generic-password -a "$USER" -s babybuddy-quackback-api-key -w')
  }
}

async function readPost(id) {
  try {
    return live({ ...(await api(`/posts/${id}`)).data, id })
  } catch (error) {
    if (error.status === 404 || error.status === 400) fail(`${id}: Quackback has no such post\n${error.message}`)
    throw error
  }
}

/// Reads every request from Quackback and checks every issue for them before writing anything.
export async function openIssue(argv) {
  const args = openIssueArgs(argv)
  loadApiKey()
  const posts = []
  for (const id of args.ids) posts.push(await readPost(id))

  // Search narrows the list; postIds on each body decides.
  const issues = args.ids.flatMap((id) => JSON.parse(gh(['issue', 'list', '--state', 'all', '--search', id,
    '--limit', '100', '--json', 'url,body'])))
  const target = args.to && JSON.parse(gh(['issue', 'view', args.to, '--json', 'url,body']))
  const dupes = duplicates(args.ids, target ? [target, ...issues] : issues)
  if (dupes.length) fail(`${dupes.map((d) => `${d.id} is already named by ${d.url}`).join('\n')}\nNothing was written.`)

  const title = args.title ?? posts[0].title
  const body = target ? appendedBody(target.body, posts) : issueBody(posts)
  if (args.dryRun || DRY_RUN) {
    console.log(`${target ? `issue: ${target.url}` : `title: ${title}`}\nlabels: ${LABEL}\n` +
      `milestone: ${args.milestone ?? 'none'}\n\n${body}`)
    return
  }
  if (!JSON.parse(gh(['label', 'list', '--search', LABEL, '--json', 'name'])).some((l) => l.name === LABEL)) {
    gh(['label', 'create', LABEL, '--description', 'Asked for on feedback.babybuddy.app'])
  }
  const milestone = args.milestone ? ['--milestone', args.milestone] : []
  if (target) {
    gh(['issue', 'edit', target.url, '--body-file', '-', '--add-label', LABEL, ...milestone], body)
    console.log(target.url)
  } else {
    console.log(gh(['issue', 'create', '--title', title, '--body-file', '-', '--label', LABEL, ...milestone], body).trim())
  }
}

function fail(message) {
  throw new Error(message)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, a, b] = process.argv.slice(2)
  try {
    if (command === 'open-issue') {
      await openIssue(process.argv.slice(3))
    } else if (command === 'issue' && a) {
      await issueEvent(JSON.parse(readFileSync(a, 'utf8')))
    } else if (command === 'ship' && a && b) {
      const notesFile = process.env.RELEASE_NOTES ?? new URL('../Docs/release-notes.md', import.meta.url)
      await ship(a, b, postIds(readFileSync(0, 'utf8')), readFileSync(notesFile, 'utf8'))
    } else {
      console.error('usage: quackback.mjs issue <event.json> | ship <version> <published-at> < bodies\n' +
        '       quackback.mjs open-issue <request>... [--to <issue>] [--milestone <version>] [--title "<text>"] [--dry-run]')
      process.exit(2)
    }
  } catch (error) {
    console.error(`::error::${error.message.split('\n')[0]}`)
    console.error(error.message)
    process.exit(1)
  }
}
