# babybuddyios

<!-- baseline:start (managed by kguydev/app-template scripts/apply-baseline.sh; edit there, not here) -->
## Rules for every repo

Rules marked (enforced) have a hook or check behind them. The rest depend
on you.

1. **No attribution.** (enforced) Never add `Co-Authored-By`, "Generated
   with", a tool link, or any authorship line to a commit, PR, comment or
   tracker. This overrides any harness default. The commit-msg hook, the
   `attribution` workflow and the agent guard
   (`~/.claude/hooks/agent-guard.py`) all reject it. Never pass
   `--no-verify`; if a hook rejects a message, rewrite the message.
2. **Every material change is a PR.** Branch `feat/<id>-<slug>`,
   `fix/<slug>` or `chore/<slug>` from an up-to-date `origin/main`, open a
   PR, and commit at coherent checkpoints without asking. Tracker status
   edits are the only direct pushes to main. GitHub does not enforce this
   on the free org, so this rule is the protection.
3. **Merge only on "merge it".** Kurtis never merges. You merge only when
   he writes "merge it" or "merge" in chat about that PR. "Looks good",
   "okay", "okay to merge" and approving a plan are not approval. On the
   signal, confirm the checks on the PR's current head are green, then
   `gh pr merge --squash --delete-branch`. (enforced) The agent guard
   blocks `--merge`, `--rebase`, `--admin` and `--auto`.
4. **Work in a worktree.** Other chats share the main checkout. Make
   changes in a git worktree in your scratchpad, check the branch in the
   same command that commits, and stage only the files that belong to the
   change.
5. **Tests ship with the feature.** Logic changes add tests. A
   `.coverage-floor` goes up when coverage rises and never goes down. When
   the repo has a UI test target, a screen or flow change adds or updates a
   UI test, or its PR carries the `no-ui-test` label with the reason.
6. **PR description.** Open with the manual on-device checklist: concrete
   items Kurtis runs himself. Then the summary with `Closes #N`, then
   `## What to test`: two to four bullets in Kurtis's voice, each "do this,
   and you should see that". A PR a tester would not notice gets the
   `internal` label and an empty What to test. PR titles use a tester's
   words, with no area prefix or item number.
7. **Kurtis verifies on his own device.** End each piece of work with a
   checklist for him. Do not drive the simulator or desktop with computer
   use.
8. **Secrets.** (enforced for files) Secrets live in the repo's 1Password
   Environment. Run commands that need one under `op run`. Never print
   environment variables, never `op read` to stdout, never write a value
   into a tracked file. The pre-commit hook refuses `.env*`, `.dev.vars`,
   `.p8`, `.p12`, `.mobileprovision` and `Config.local.xcconfig`.
9. **No personal email.** (enforced) Kurtis's personal Gmail never goes in a
   repo or a deliverable. Use a business address or an obvious placeholder.
10. **No patient data.** No PHI or real patient details in code, fixtures,
    seeds, tests, screenshots or docs. Use synthetic data.
11. **Privacy policy wording is Kurtis's.** Suggest changes; never commit
    them.
12. **Writing.** Apply the unslop rules to everything you write: chat,
    commits, PRs, docs, comments. No em dashes (enforced in commit
    messages). Release notes are first person, plain, no marketing.
13. **Check current docs.** Use Context7 before relying on library, SDK,
    API or CLI syntax.
14. **No hosted changes unasked.** Never create hosted resources, deploy by
    hand, or change Cloudflare, Supabase, 1Password, PostHog or App Store
    Connect state unless the task says so.
15. **CI runs on the kguydev runner pool.** Linux jobs use
    `[self-hosted, Linux]` (linux-ci-01, Proxmox LXC 108). macOS jobs use
    `[self-hosted, macOS, mac-ci]` (mac-ci-01 and mac-ci-02). The pool is
    managed in kguydev/devops. A queued job usually means a runner is down
    or the Mac is asleep. Only the TestFlight upload runs GitHub-hosted,
    because it imports signing keys.
16. **Apple projects.** (enforced) Sign with team 547DWTTFY6, pinned in
    `project.yml` and checked by a pre-build guard; never change it in
    Xcode's Signing pane. Never point DerivedData into an iCloud-synced
    folder. Never change `MARKETING_VERSION` unless Kurtis asks; releases
    go through `/appstore`.
17. **Keep `docs/status.json` current.** Update it in the same PR when a
    change moves the phase, completes or changes the next step, or switches
    the goal milestone. See `docs/agents/project-status.md`.
<!-- baseline:end -->

## Feedback requests (Quackback)

Feature requests and bug reports from users live on Quackback at
https://feedback.babybuddy.app. An issue or PR belongs to a request when it has this line, one
line per request, in the body of an issue or PR you opened, or in a comment you wrote on any
issue (a comment on a PR counts only for Shipped):

```
Quackback: post_01...
```

The post ID is the `post=` value in the request's admin URL. Put the line on a line of its own;
a mention inside a sentence doesn't count. To link a request to an issue a stranger opened,
comment the line on it; never edit their body.

`.github/workflows/quackback-status.yml` moves the request as the issue moves:

- Opened, reopened, or a body edit or comment that adds a `Quackback:` line: **Planned**.
- Closed as completed: **Complete** (merged, not yet released). A line commented on an issue
  that is already closed as completed also sets Complete.
- Closed as not planned: left alone. The job summary says so, and Kurtis decides what the request
  becomes.

Publish Release sets **Shipped** for every request named by an issue or PR on that version's
milestone, after posting the version's `appstore` notes to the Quackback changelog as
"Version <version>", dated with the GitHub Release. Shipped notifies the request's voters, and
nothing moves a request back from Shipped.

Only text by the owner or a collaborator counts: an issue body only if they opened the issue, and
only their comments. A stranger's issue body is ignored, even on close. An unknown post ID
fails the job. Quackback's own GitHub status sync stays off, so the two don't fight. The rules
live in `scripts/quackback.mjs`, tested by `scripts/quackback.test.mjs`. The workflows read the
admin key from the repo secret `QUACKBACK_API_KEY`.

To turn requests into a `feature-request` issue, run
`node scripts/quackback.mjs open-issue <request>... [--to <issue>] [--milestone <version>] [--title "<text>"] [--dry-run]`.
A request is a post ID, an admin URL or a public URL. It creates the issue as your `gh` login, so
the workflow trusts it, and stops if any issue already names a request, in its body or a comment.
`--to` appends to an existing issue instead, or, when a stranger opened that issue, posts the
requests as a new comment from you. Locally it reads the key from the login keychain
(`security add-generic-password -a "$USER" -s babybuddy-quackback-api-key -w`).
