#!/usr/bin/env node
// Keeps request statuses on Quackback (feedback.babybuddy.app) in step with GitHub. An issue or PR
// belongs to a request when its body has a line `Quackback: post_<id>`, one line per request.
//
//   node scripts/quackback.mjs issue <event.json>          an `issues` event: Planned or Complete
//   node scripts/quackback.mjs ship <version> <published>  the changelog entry, then Shipped
//
// `ship` reads issue and PR bodies on stdin and the notes from Docs/release-notes.md (or
// `RELEASE_NOTES=<path>`). `<published>` is an ISO 8601 time, the GitHub Release's publishedAt.
//
// QUACKBACK_API_KEY is an admin API key. QUACKBACK_URL overrides the API base. QUACKBACK_DRY_RUN=1
// still reads from Quackback, so an unknown post still fails, but prints each write instead of
// sending it.
//
// No dependencies, on purpose, like release.mjs.

import { appendFileSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { appStoreNotes } from './release.mjs'

const API = process.env.QUACKBACK_URL ?? 'https://feedback.babybuddy.app/api/v1'
const DRY_RUN = process.env.QUACKBACK_DRY_RUN === '1'

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

function fail(message) {
  throw new Error(message)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, a, b] = process.argv.slice(2)
  try {
    if (command === 'issue' && a) {
      await issueEvent(JSON.parse(readFileSync(a, 'utf8')))
    } else if (command === 'ship' && a && b) {
      const notesFile = process.env.RELEASE_NOTES ?? new URL('../Docs/release-notes.md', import.meta.url)
      await ship(a, b, postIds(readFileSync(0, 'utf8')), readFileSync(notesFile, 'utf8'))
    } else {
      console.error('usage: quackback.mjs issue <event.json> | ship <version> <published-at> < bodies')
      process.exit(2)
    }
  } catch (error) {
    console.error(`::error::${error.message.split('\n')[0]}`)
    console.error(error.message)
    process.exit(1)
  }
}
