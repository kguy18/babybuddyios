#!/usr/bin/env python3
"""Checks a built app before release.yml uploads it.

    scripts/check-build.py <path to .app> [team ID]

- Every Info.plist key that project.yml fills from a Config.xcconfig variable
  has a value, in the app and in each extension under PlugIns/. An empty one
  means the 1Password Environment lacks it. A key a bundle does not have is
  skipped.
- Each extension carries the app's version and build number.
- With a team ID, the app and each extension are signed by that team.

REPO_ROOT points at another checkout (the test). Never prints a value.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("REPO_ROOT") or Path(__file__).resolve().parent.parent)


def problems(app, team=None):
    settings = json.loads((ROOT / "appstore.json").read_text())
    project_yml = ROOT / settings["projectYml"]
    # appstore.json's configFile names the xcconfig when it is not Config.xcconfig beside project.yml.
    config = ROOT / settings["configFile"] if "configFile" in settings else project_yml.parent / "Config.xcconfig"
    declared = set(re.findall(r"^([A-Z0-9_]+) *=", config.read_text(), re.M)) if config.exists() else set()
    # project.yml lines such as `RevenueCatAPIKey: "$(REVENUECAT_API_KEY)"`,
    # and a key named after its variable however project.yml writes it.
    filled = {(key, var) for key, var in re.findall(r'^ *(\w+): *"?\$\(([A-Z0-9_]+)\)"? *$', project_yml.read_text(), re.M) if var in declared}
    filled |= {(var, var) for var in declared}

    bundles = [app, *sorted(app.glob("PlugIns/*.appex"))]
    info = {b: plistlib.loads((b / "Info.plist").read_bytes()) for b in bundles}
    found = []
    for b in bundles:
        for key, var in sorted(filled):
            value = info[b].get(key)
            if isinstance(value, str) and not value.strip():
                found.append(f"{var} is empty in the release build ({b.name}, Info.plist key {key}). Add it to the 1Password Environment.")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if info[b].get(key) != info[app].get(key):
                found.append(f"{b.name} has {key} {info[b].get(key)}, but {app.name} has {info[app].get(key)}.")
        if team:
            signed = subprocess.run(["codesign", "-dv", str(b)], capture_output=True, text=True).stderr
            by = re.search(r"^TeamIdentifier=(.*)$", signed, re.M)
            if not by or by.group(1) != team:
                found.append(f"{b.name} is signed by team {by.group(1) if by else 'none'}, not {team}.")
    return found, [b.name for b in bundles]


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    found, names = problems(Path(sys.argv[1]), *sys.argv[2:3])
    for line in found:
        print(f"::error::{line} Nothing was uploaded.")
    if found:
        sys.exit(1)
    print(f"Build check passed: {', '.join(names)}" + (f", signed by {sys.argv[2]}" if len(sys.argv) > 2 else ""))
