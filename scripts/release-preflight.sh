#!/usr/bin/env bash
# What a release depends on beyond the binary, since the newest v* tag on
# origin/main. A report, not a gate: it reads git and GitHub, needs no
# secret, and exits 0. A heading appears only when it has something to say.
# Paths come from appstore.json.
#
#   scripts/release-preflight.sh
cd "$(dirname "$0")/.." || exit 0
git fetch -q origin --tags 2>/dev/null

cfg() { node -p "require('./appstore.json')['$1'] ?? ''"; }
PROJECT_YML=$(cfg projectYml)
PROJECT_DIR=$(dirname "$PROJECT_YML")
APP_DIR=$(cfg appDir)
SHOTS=$(cfg screenshotsDir)

LAST=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [ -n "$LAST" ]; then
  SINCE=$LAST
  echo "Since $LAST"
else
  SINCE=$(git rev-list --max-parents=0 origin/main | tail -1)
  echo "Since the first commit (no v tag yet)"
fi
changed() { git diff --name-only "$SINCE"..origin/main -- "$@"; }
# Lines that differ between two texts, as +new and -old.
difflines() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | sed -n 's/^> \(..*\)/  + \1/p; s/^< \(..*\)/  - \1/p'; }
# A YAML key's block: the key line and everything indented under it, less comments.
yaml_block() { # rev file key
  git show "$1:$2" 2>/dev/null | awk -v key="$3:" '
    { n = match($0, /[^ ]/) - 1 }
    on && NF && n <= ind { on = 0 }
    on && /^ *#/ { next }
    on { print; next }
    $1 == key { on = 1; ind = n; print }'
}

# What App Review reads from the bundle. Info.plist may be generated from
# project.yml's info block, so that block is compared too.
REVIEW=$(changed '*.entitlements' '*Info.plist' | sed 's/^/  /')
if [ -n "$(changed "$PROJECT_YML")" ]; then
  for KEY in info entitlements; do
    D=$(difflines "$(yaml_block "$SINCE" "$PROJECT_YML" $KEY)" "$(yaml_block origin/main "$PROJECT_YML" $KEY)")
    [ -n "$D" ] && REVIEW+="${REVIEW:+$'\n'}$D"
  done
fi
[ -n "$REVIEW" ] && printf '\nInfo.plist and entitlements (App Review sees these)\n%s\n' "$REVIEW"

# App Privacy answers: the privacy manifest and the third-party SDK list.
PRIVACY=$(changed '*PrivacyInfo.xcprivacy' '*Acknowledgements.json' | sed 's/^/  /')
[ -n "$PRIVACY" ] && printf '\nApp Privacy answers may need a look (docs/app-store/CHECKLIST.md)\n%s\n' "$PRIVACY"

# The backend this release talks to. worker-deploy.yml deploys it on merge.
MIGRATIONS=$(git diff --name-only --diff-filter=A "$SINCE"..origin/main -- worker/migrations | grep '\.sql$' | sed 's/^/  /')
[ -n "$MIGRATIONS" ] && printf '\nworker/migrations (applied on merge; the release depends on them)\n%s\n' "$MIGRATIONS"
WORKER=$(changed worker/src | sed 's/^/  /')
[ -n "$WORKER" ] && printf '\nworker/src changed (check its Worker deploy run is green before release)\n%s\n' "$WORKER"

# Build pipeline, since the last upload rather than the last release.
BLAST=$(git tag -l 'build/*' --sort=-creatordate | head -1)
if [ -z "$BLAST" ]; then
  printf '\nBuild pipeline\n  No build/* tag yet: run release.yml with dry_run=true first.\n'
else
  PIPE=$(git diff --name-only "$BLAST"..origin/main -- .github/workflows/release.yml "$PROJECT_DIR/ExportOptions.plist" \
    appstore.json "$PROJECT_DIR/Config.xcconfig" "$PROJECT_DIR/scripts/secrets.sh" | sed 's/^/  /')
  SIGN=$(git diff "$BLAST"..origin/main -- "$PROJECT_YML" |
    grep -E '^[-+][^-+].*(DEVELOPMENT_TEAM|CODE_SIGN|PROVISIONING_PROFILE|PRODUCT_BUNDLE_IDENTIFIER|bundleIdPrefix|EXPECTED_TEAM|packages:|from: )' | sed 's/^/  /')
  PIPE+="${PIPE:+${SIGN:+$'\n'}}$SIGN"
  [ -n "$PIPE" ] &&
    printf '\nBuild pipeline changed since %s: offer a dry run (release.yml dry_run=true) first\n%s\n' "$BLAST" "$PIPE"
fi

# Screenshots. A public repo keeps them outside git, so only a private one has a date to compare.
if [ "$(gh repo view --json visibility --jq .visibility 2>/dev/null)" != PRIVATE ]; then
  printf '\nScreenshots\n  Public repo: they live outside git. /kguydev:appstore screenshots checks them with an upload dry run.\n'
else
  read -r VIEWS VIEWS_DAY <<<"$(git log -1 --format='%ct %cs' origin/main -- "$APP_DIR/Views")"
  if git ls-tree -r --name-only origin/main -- "$SHOTS" | grep -q '\.png$'; then
    read -r SHOT SHOT_DAY <<<"$(git log -1 --format='%ct %cs' origin/main -- "$SHOTS")"
    [ "${VIEWS:-0}" -gt "${SHOT:-0}" ] &&
      printf '\nScreenshots\n  %s/Views changed %s, the screenshots in %s on %s. /kguydev:appstore screenshots checks them.\n' \
        "$APP_DIR" "$VIEWS_DAY" "$SHOTS" "$SHOT_DAY"
  else
    printf '\nScreenshots\n  %s has no PNGs on main. /kguydev:store-screenshots makes them.\n' "$SHOTS"
  fi
fi
exit 0
