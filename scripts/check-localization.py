#!/usr/bin/env python3
"""Check the string catalogs: English must be complete, other languages are optional.

Every translation that exists must keep the English format arguments, be non-empty and have
an `other` plural form. Missing translations fall back to English, so they are reported as
coverage and never fail the check. `--missing <lang>` lists the keys a language lacks.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(lld|llu|ld|lu|d|i|u|f|e|g|@|%)")
errors = []


def arguments(text, where):
    """Map each format argument position to its type, e.g. {1: "lld", 2: "@"}."""
    result, position = {}, 1
    for match in FORMAT.finditer(text):
        if match[2] == "%":
            continue
        index = int(match[1]) if match[1] else position
        position += 1
        if result.get(index, match[2]) != match[2]:
            errors.append(f"{where}: argument {index} has two types in {text!r}")
        result[index] = match[2]
    if "%" in FORMAT.sub("", text):
        errors.append(f"{where}: invalid format specifier in {text!r}")
    return result


def units(localization, where):
    """The string units of a localization: one, or one per plural form."""
    if "stringUnit" in localization:
        return {"": localization["stringUnit"]}
    plural = localization.get("variations", {}).get("plural")
    if not plural:
        errors.append(f"{where}: no stringUnit or plural variations")
        return {}
    if "other" not in plural:
        errors.append(f"{where}: plural has no 'other' form")
    return {form: value["stringUnit"] for form, value in plural.items()}


parser = argparse.ArgumentParser()
parser.add_argument("--missing", metavar="LANG", help="list the keys LANG has no translation for")
args = parser.parse_args()

catalogs = sorted(ROOT.glob("Sources/**/*.xcstrings")) + sorted(ROOT.glob("Widgets/**/*.xcstrings"))
loaded = {path.relative_to(ROOT): json.loads(path.read_text()) for path in catalogs}
languages = {lang for catalog in loaded.values() for entry in catalog["strings"].values()
             for lang in entry.get("localizations", {})} - {"en"}
total, translated, missing = 0, dict.fromkeys(languages, 0), {lang: [] for lang in languages}
for name, catalog in loaded.items():
    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{name}: sourceLanguage must be en")
    for key, entry in catalog["strings"].items():
        localizations = entry.get("localizations", {})
        # Without an en localization, Xcode uses the key itself as the English text.
        english = units(localizations["en"], f"{name} {key!r} en") if "en" in localizations else {"": {"value": key}}
        if not all(unit.get("value", "").strip() for unit in english.values()):
            errors.append(f"{name} {key!r}: empty English value")
        expected = arguments((english.get("other") or next(iter(english.values()), {})).get("value", ""), key)
        if "%" in key and arguments(key, key) != expected:
            errors.append(f"{name} {key!r}: English arguments differ from the key")
        if entry.get("shouldTranslate") is False:
            continue
        total += 1
        for lang in languages:
            if lang not in localizations:
                missing[lang].append(f"{name}: {key}")
                continue
            where = f"{name} {key!r} {lang}"
            forms = units(localizations[lang], where)
            for form, unit in forms.items():
                value = unit.get("value", "")
                if not value.strip():
                    errors.append(f"{where} {form}: empty value")
                elif arguments(value, where) != expected:
                    errors.append(f"{where} {form}: arguments {arguments(value, where)} != {expected} in {value!r}")
            if forms and all(unit.get("state") == "translated" for unit in forms.values()):
                translated[lang] += 1
            else:
                missing[lang].append(f"{name}: {key}")

spec = (ROOT / "project.yml").read_text()
if "developmentLanguage: en" not in spec:
    errors.append("project.yml: developmentLanguage must be en")
if "- path: Sources/Shared" not in spec:
    errors.append("project.yml: the widget must include Sources/Shared, which holds the shared catalog")

if args.missing:
    print("\n".join(missing.get(args.missing, [])))
    sys.exit(1 if errors else 0)

coverage = [f"{lang}: {translated[lang] * 100 // total}%, {len(missing[lang])} missing"
            for lang in sorted(translated)]
report = f"localization: {total} keys" + ("" if errors else ", English complete, translations valid") + "".join(f"\n  {line}" for line in coverage)
print(report)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write("### Localization coverage\n\n" + "".join(f"- {line}\n" for line in coverage or ["English only"]))
for error in errors:
    print(f"error: {error}", file=sys.stderr)
sys.exit(1 if errors else 0)
