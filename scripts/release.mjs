#!/usr/bin/env node
// Reads Docs/release-notes.md, the one place release notes are written.
//
//   node scripts/release.mjs validate        every section, as CI runs it
//   node scripts/release.mjs notes 1.1.0     the App Store text, byte for byte
//   node scripts/release.mjs body 1.1.0      the GitHub Release body, as Markdown
//
// No dependencies, on purpose: this runs in CI and in the release workflows with nothing installed.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export const APP_STORE_URL = 'https://apps.apple.com/app/id6788966667'
/// App Store Connect's cap on "What's New in This Version".
export const APP_STORE_LIMIT = 4000

const VERSION = /^\d+\.\d+(\.\d+)?$/
const BLOCKS = ['appstore', 'whatsnew']

/// Every `## ` section in file order, with its labelled fenced blocks. Lenient by design — it
/// reports what is there, and `validate` decides what is wrong with it.
export function sections(markdown) {
  const found = []
  let section = null
  let label = null // the open fence's info string, or null outside a fence
  let lines = []

  for (const line of markdown.split('\n')) {
    if (label !== null) {
      if (line.trimEnd() === '```') {
        // A repeated label keeps the first block, so a stray second one can't replace the text.
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

/// Everything wrong with the file, as readable strings. Empty means it is fine.
export function validate(markdown) {
  const errors = []
  const seen = new Set()
  const all = sections(markdown)
  if (all.length === 0) errors.push('no `## <version>` sections found')

  for (const { heading, version, blocks } of all) {
    if (!heading.startsWith('## ') || !VERSION.test(version)) {
      errors.push(`malformed heading "${heading}": expected "## <major>.<minor>[.<patch>]"`)
      continue
    }
    if (seen.has(version)) errors.push(`${version}: more than one section`)
    seen.add(version)

    for (const name of BLOCKS) {
      if (!(name in blocks)) errors.push(`${version}: no \`${name}\` block`)
      else if (blocks[name].trim() === '') errors.push(`${version}: the \`${name}\` block is empty`)
    }
    const length = [...(blocks.appstore ?? '')].length
    if (length > APP_STORE_LIMIT) {
      errors.push(`${version}: the \`appstore\` block is ${length} characters; App Store Connect allows ${APP_STORE_LIMIT}`)
    }
  }
  return errors
}

/// The `appstore` block for `version`, exactly as written. Throws rather than return text from a
/// section that would not pass `validate` — this is what gets sent to App Store Connect.
export function appStoreNotes(markdown, version) {
  const mine = validate(markdown).filter((e) => e.startsWith(`${version}:`))
  if (mine.length) throw new Error(mine.join('\n'))
  const section = sections(markdown).find((s) => s.version === version)
  if (!section) throw new Error(`${version}: no section in the release notes`)
  return section.blocks.appstore
}

/// The GitHub Release body: `#New` becomes a heading, the bullets are already Markdown, and the
/// App Store link leads, because the release carries no build to download.
// ponytail: the store text is not escaped for Markdown. It is plain prose today; escape `*`, `_`
// and `<` here if a note ever needs them literally.
export function githubBody(notes, url = APP_STORE_URL) {
  const body = notes.replace(/^#\s*(\S.*)$/gm, '### $1')
  return `**[Get it on the App Store](${url})**\n\n${body.trim()}\n`
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, version] = process.argv.slice(2)
  const markdown = readFileSync(new URL('../Docs/release-notes.md', import.meta.url), 'utf8')
  try {
    if (command === 'validate') {
      const errors = validate(markdown)
      for (const e of errors) console.error(`::error file=Docs/release-notes.md::${e}`)
      if (errors.length) process.exit(1)
      console.log(`release notes: ${sections(markdown).length} sections, all valid`)
    } else if (command === 'notes' && version) {
      process.stdout.write(appStoreNotes(markdown, version))
    } else if (command === 'body' && version) {
      process.stdout.write(githubBody(appStoreNotes(markdown, version)))
    } else {
      console.error('usage: release.mjs validate | notes <version> | body <version>')
      process.exit(2)
    }
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}
