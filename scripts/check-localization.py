#!/usr/bin/env python3
"""Validate catalog completeness, format arguments, plurals and bundled release notes."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r"%(?:(\d+)\$)?(lld|@)")


def arguments(text):
    result = {}
    next_index = 1
    for match in FORMAT.finditer(text):
        index = int(match[1]) if match[1] else next_index
        next_index += 1
        assert index not in result, f"Repeated format argument in {text!r}"
        result[index] = match[2]
    remainder = FORMAT.sub("", text)
    assert "%" not in remainder, f"Invalid format specifier in {text!r}"
    return result


catalogs = sorted(ROOT.glob("Sources/**/*.xcstrings"))
assert len(catalogs) == 2, "Expected Localizable and InfoPlist catalogs"
count = 0
for path in catalogs:
    catalog = json.loads(path.read_text())
    assert catalog["sourceLanguage"] == "en", path
    for key, entry in catalog["strings"].items():
        expected = arguments(key)
        assert set(entry["localizations"]) == {"en", "de-DE"}, key
        for language, localization in entry["localizations"].items():
            if "variations" in localization:
                forms = localization["variations"]["plural"]
                assert set(forms) == {"one", "other"}, (key, language)
                assert list(expected.values()).count("lld") == 1, key
                units = [form["stringUnit"] for form in forms.values()]
            else:
                units = [localization["stringUnit"]]
            for unit in units:
                assert unit["state"] == "translated", (key, language)
                assert unit["value"].strip(), (key, language)
                assert arguments(unit["value"]) == expected, (key, language, unit)
        count += 1

strings = json.loads((ROOT / "Sources/Shared/Localizable.xcstrings").read_text())["strings"]
notes = (ROOT / "Docs/release-notes.md").read_text()
for block in re.findall(r"```whatsnew\n(.*?)```", notes, re.S):
    for line in block.splitlines():
        if line.startswith("- "):
            parts = line[2:].split(" | ")
            for text in parts[1:] if len(parts) > 1 else parts:
                assert text in strings, f"Untranslated bundled release note: {text}"

spec = (ROOT / "project.yml").read_text()
assert "developmentLanguage: en" in spec
assert "- path: Sources/Shared" in spec, "Widgets must include the shared catalog"
print(f"localization: {count} entries, English and de-DE complete; arguments and plurals valid")
