#!/usr/bin/env python3
"""Entitlements for an archive that was built unsigned.

    scripts/entitlements.py embed  <project.xcodeproj> <path to .app> <team ID>
    scripts/entitlements.py verify <project.xcodeproj> <path to .app> <team ID>

An unsigned archive carries no entitlements, and export re-signs each bundle
with the ones already on it. `embed` gives the app and each extension under
PlugIns/ its target's entitlements with an ad-hoc signature, so export only
has to fill in the profile's values. `verify` checks that every key is still
there on what export signed.
"""
import json
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def sources(project, team):
    """Each product's entitlements, by bundle name, with the team prefix filled in."""
    settings = json.loads(run("xcodebuild", "-project", project, "-alltargets", "-configuration", "Release", "-showBuildSettings", "-json"))
    found = {}
    for target in settings:
        s = target["buildSettings"]
        if s.get("CODE_SIGN_ENTITLEMENTS"):
            text = (Path(s["SRCROOT"]) / s["CODE_SIGN_ENTITLEMENTS"]).read_text()
            for variable in ("$(AppIdentifierPrefix)", "$(TeamIdentifierPrefix)"):
                text = text.replace(variable, f"{team}.")
            found[s["FULL_PRODUCT_NAME"]] = text.encode()
    return found


def main(action, project, app, team):
    app = Path(app)
    wanted = sources(project, team)
    failed = False
    # Extensions first: the app's signature covers them.
    for bundle in [*sorted(app.glob("PlugIns/*.appex")), app]:
        if bundle.name not in wanted:
            print(f"{bundle.name}: no entitlements")
            continue
        if action == "embed":
            with tempfile.NamedTemporaryFile(suffix=".entitlements") as file:
                file.write(wanted[bundle.name])
                file.flush()
                run("codesign", "-f", "-s", "-", "--entitlements", file.name, str(bundle))
            print(f"{bundle.name}: entitlements embedded")
        else:
            have = plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(bundle)).encode() or b"<plist><dict/></plist>")
            missing = [key for key in plistlib.loads(wanted[bundle.name]) if key not in have]
            if missing:
                print(f"::error::{bundle.name} lost entitlements at export: {', '.join(missing)}. Nothing was uploaded.")
                failed = True
            else:
                print(f"{bundle.name}: entitlements kept")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[1] not in ("embed", "verify"):
        sys.exit(__doc__)
    main(*sys.argv[1:])
