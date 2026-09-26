---
name: babybuddy-release
description: Conduct a Baby Buddy Companion App Store release end to end — notes from the milestone, the release-prep PR, Prepare Release, the archive, Publish Release. Resumable; run it again at each stage. Usage /babybuddy-release <version>, e.g. /babybuddy-release 1.1.0
---

# /babybuddy-release <version>

You conduct a release; the workflows enforce it. Never re-implement a check that Prepare Release
or Publish Release already makes — run the workflow and read whether it refused. A release takes
days, so this skill is invoked several times: **work out the stage first, then continue from it.**

`$ARGUMENTS` is the version (`1.1.0`). With no version, ask — never guess one. Being invoked with a
version **is** Kurtis's explicit request to change `MARKETING_VERSION` to it (CLAUDE.md otherwise
forbids that). It must be `major.minor[.patch]`, no `v`.

## Rules that do not bend

- Kurtis does these himself; prompt him and wait, never attempt them: create the version in App
  Store Connect, approve the wording of the notes, merge any PR, upload/select the build, submit
  for review, press Release. You merge only if he says "merge it" about that PR.
- Every change is a branch + PR, made in a **git worktree in the scratchpad** — other chats share
  the main working tree, and `checkout -b` there moves their HEAD.
- No attribution trailers in commits or PR bodies. Merge commits, not squash.
- Never touch a secret. The App Store Connect key lives in the `release` environment and in
  `~/.appstoreconnect/private_keys/`; you never read it, print it, or ask for it.
- Never move or delete a published tag or release.

## 1. Work out the stage

```bash
git fetch -q origin --tags
V=<version>
git show origin/main:project.yml | grep -E '(MARKETING|CURRENT_PROJECT)_VERSION:'
gh pr list --state all --search "chore/release-$V in:head" --json number,state,headRefName
gh release view "v$V" --json isDraft,targetCommitish,url 2>/dev/null || echo "no release"
gh run list --workflow prepare-release.yml --limit 3 --json databaseId,conclusion,displayTitle,createdAt
```

| What you find | Stage |
| --- | --- |
| `MARKETING_VERSION` ≠ V, no release-prep PR | **A** — write the notes, open the PR |
| Release-prep PR open | **A, waiting** — report CI, remind him to merge |
| `MARKETING_VERSION` = V on main, no release | **B** — Prepare Release |
| Draft release exists | **C/D** — ask: archived? on TestFlight, being tried? submitted? rejected? live? |
| Release published | **Done** — section E's wrap-up only |

Say which stage you found and why, in one line, before doing anything.

## A. Notes and the release-prep PR

1. Remind him to create version V in App Store Connect now if he has not (Prepare Release needs it).
2. Report on the milestone titled exactly V, then **wait**:
   ```bash
   N=$(gh api 'repos/kguy18/babybuddyios/milestones?state=all' --jq ".[] | select(.title==\"$V\") | .number")
   gh api "repos/kguy18/babybuddyios/issues?milestone=$N&state=all&per_page=100" --jq '.[] | "\(.state)\t#\(.number)\t\(.title)"'
   LAST=$(git tag -l 'v*' --sort=-v:refname | head -1)
   SINCE=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ $LAST)   # the tagged commit, to the second
   gh pr list --state merged --search "merged:>=${SINCE%T*}" --limit 100 --json number,title,milestone,mergedAt,labels \
     --jq ".[] | select(.milestone==null and .mergedAt > \"$SINCE\" and ([.labels[].name] | index(\"internal\") | not)) | \"#\(.number)\t\(.title)\""
   ```
   - Anything still **open** in the milestone: ship without it, or wait?
   - Every merged PR since `$LAST` with **neither** a milestone **nor** the `internal` label is
     unsorted. For each, he decides: user-visible (`gh pr edit <n> --milestone V`) or not
     (`gh pr edit <n> --add-label internal`). Before asking, check whether it touched `Sources/` or
     `Widgets/` and read that part of the diff — a PR titled as tests or CI can carry a real fix
     the tests found (#120, #121, #123 and #124 all did), and those belong in the notes. The list
     should be empty by the time you draft.
3. Draft the `## V` section for `Docs/release-notes.md` from the milestone's closed issues and PRs —
   read their bodies, and each PR's `## What to test`; issue wording is closer to release-note
   language than a PR title. Both blocks, in the format the file's own header documents:
   - `appstore`: plain text, `#New` / `#Improved` / `#Fixed`, full-sentence bullets, his voice
     (first person singular, plain, no marketing). Read the older sections for tone. ≤ 4,000 chars.
   - `whatsnew`: `- <icon> | <title ≤ ~32 chars> | <body ≤ ~90 chars>` under `#New`; one plain line
     each under `#Fixed`. Icons: `sync alert photo guard timer widget speed new`.
   Show him both blocks in chat. Iterate until he approves the wording. **The `whatsnew` block is
   bundled into the app — it must be final before the archive.** The `appstore` block can still be
   fixed by rerunning Prepare Release until he submits.
4. In a worktree from `origin/main`, branch `chore/release-V`: set `MARKETING_VERSION: "V"` and
   `CURRENT_PROJECT_VERSION: "1"` in `project.yml`; insert the section above the newest existing
   `## ` heading; run `node scripts/release.mjs validate` and `node --test scripts/release.test.mjs`.
5. Open the PR titled `Version V (build 1)`, milestone V, using the PR template. (Any other PR
   you open that a user would not notice — tooling, CI — gets the `internal` label, no milestone.) `## What to test`
   summarises the release for TestFlight testers. Watch CI (`gh pr checks <n> --watch`); a single UI
   test failing on a PR with no app code is a flake — `gh run rerun <run> --failed` once, and tell
   him. Then stop: merging is his.

## B. Prepare Release

Only once the release-prep PR has merged.

```bash
gh workflow run prepare-release.yml --ref main -f version=$V
```

Watch it (`gh run list --workflow prepare-release.yml --limit 1`, `gh run watch <id> --exit-status`).

- A good run takes about ten seconds and every step succeeds: `Only from main`, `This commit is
  that version, with notes, and not yet published`, `Send the notes to App Store Connect` (its log
  says `V: What's New updated, <n> characters`), `Draft the GitHub Release`, `Summary`. A rerun
  edits the one existing draft and retargets it to the new commit — it never makes a second.
  (Known-good: 1.1.0, runs 35601108212 and 35632975025.)
- The draft's body opens with the Download on the App Store badge, then the `appstore` text under
  `### New` / `### Improved` / `### Fixed`. Its URL is `…/releases/tag/untagged-…` until published.
- A **403** from App Store Connect on `send` means the API key's role cannot write metadata: he
  needs a new key with a higher role and to re-set the three `ASC_*` secrets. A **409** means the
  version is not editable (already submitted) — nothing to fix, tell him.
- "no iOS versions with that number" means he has not created V in App Store Connect yet.

Confirm the draft targets a 40-character SHA and is titled with the tag alone (`v$V` — never the
app's name; a release you retitle by hand gets the same), and report: version, build, SHA.

## C. Archive

Build from the draft's commit, outside `~/Documents` (iCloud stamps xattrs that break codesigning):

```bash
MAIN_TREE=/Users/kurtisguy/Documents/Projects/BabyBuddy
SHA=$(gh release view "v$V" --json targetCommitish --jq .targetCommitish)
WT="<scratchpad>/archive-$V" && git worktree add --detach "$WT" "$SHA" && cd "$WT"
# Secrets.xcconfig is gitignored, so a fresh worktree has none and `#include?` skips it silently:
# 1.1.0 shipped with no RevenueCat key and no tips because of exactly this. Copy it, then check.
cp "$MAIN_TREE/Config/Secrets.xcconfig" Config/ && xcodegen generate
BUILD=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]*)"? *$/\1/p' project.yml)
xcodebuild -project BabyBuddy.xcodeproj -scheme BabyBuddy -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$WT/../dd-$V" \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/BabyBuddy $V ($BUILD).xcarchive" \
  -allowProvisioningUpdates archive DEVELOPMENT_TEAM=547DWTTFY6
```

The team must be **547DWTTFY6** — never 7F4G4A2WGJ. Check the archive's
`Info.plist` reports version V and build `$BUILD`, **and that `RevenueCatAPIKey` and the
TelemetryDeck app ID are non-empty** (`PlistBuddy -c 'Print :RevenueCatAPIKey'` on
`Products/Applications/BabyBuddy.app/Info.plist`; never print the values). Empty means the
secrets file did not reach the worktree: do not hand that archive over. It appears in Xcode ▸ Window ▸ Organizer; from
there **he** uploads, selects the build in App Store Connect, and submits. If the command-line
archive fails on signing, fall back to `open BabyBuddy.xcodeproj` and let him Product ▸ Archive.
Remove the worktree afterwards.

## D. After Apple answers — or after he has tried it on TestFlight

Uploading is not submitting. An uploaded build reaches his internal TestFlight testers with no
review, so he may upload, try it on his device, and only then submit that same build. Ask which
of these he is in; do not assume an upload means it is with App Review.

- **He found a problem on TestFlight, before submitting:** the same path as a rejection, below.
- **Rejected, needs a new build:** the fix goes in as a normal PR on milestone V that also bumps
  `CURRENT_PROJECT_VERSION` by one (never `MARKETING_VERSION`). After he merges it, rerun **B** —
  it retargets the same draft — then **C**. Publish Release refuses if this is skipped: it compares
  the build Apple shipped with the build at the draft's commit.
- **Hotfix archived from a branch, draft retargeted by hand (1.1.1):** Publish Release rebuilds the
  body from `Docs/release-notes.md` *at the draft's target commit*. Notes merged to main after that
  commit do not reach the GitHub Release; after publishing, regenerate it from main:
  `git show origin/main:Docs/release-notes.md > /tmp/rn.md && RELEASE_NOTES=/tmp/rn.md node
  scripts/release.mjs body $V | gh release edit v$V --notes-file -`.
- **Approved, manual release:** the version sits at `PENDING_DEVELOPER_RELEASE` until he presses
  Release. Publish Release refusing then is correct, not a fault.

## E. Publish Release

When he says it is live — or just to find out; refusing is harmless and changes nothing:

```bash
gh workflow run publish-release.yml --ref main -f version=$V
```

A good run ends with `Publish` succeeded and `babybuddy.app/whatsnew/ shows V`. If the release was
already public, `The draft is the commit that shipped` and `Publish` show as skipped and it only
rebuilds the site. Failure messages are written to be read — relay them:
`… is <STATE>, not READY_FOR_DISTRIBUTION` (not live yet), `Apple shipped build X; <sha> is build Y`
(rerun B on the archived commit), `not a full commit SHA` (rerun B). A `/whatsnew/` timeout is only
a warning: check the Cloudflare build, the GitHub Release is already valid.

Wrap-up, once published:

```bash
gh release view "v$V" --json url,isDraft,name,tagName,assets   # isDraft false, name = tagName, assets []
curl -s https://babybuddy.app/whatsnew/ | grep -c ">Version $V<"
gh api -X PATCH "repos/kguy18/babybuddyios/milestones/$N" -f state=closed
```

