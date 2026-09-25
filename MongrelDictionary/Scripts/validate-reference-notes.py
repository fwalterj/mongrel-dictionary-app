#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import unicodedata
from collections import Counter
from pathlib import Path


def normalized_lookup_key(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    return value.strip().lower()


def fail(message: str) -> None:
    print(f"reference-notes validation failed: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    notes_dir = script_dir.parent / "ReferenceNotesAuthoring"

    if not notes_dir.is_dir():
        fail(f"missing directory: {notes_dir}")

    files = sorted(notes_dir.glob("*.json"))
    if not files:
        fail("no note files found")

    titles = Counter()
    lookup_keys = Counter()
    see_also_refs: list[tuple[str, str]] = []
    total_notes = 0

    for file in files:
        try:
            payload = json.loads(file.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            fail(f"{file.name} is not valid JSON: {exc}")

        if not isinstance(payload, list):
            fail(f"{file.name} must contain a JSON array")

        if not payload:
            fail(f"{file.name} is empty")

        for index, note in enumerate(payload, start=1):
            if not isinstance(note, dict):
                fail(f"{file.name} item {index} must be an object")

            required = ["title", "sourceTitle", "summary", "aliases", "chips"]
            for field in required:
                if field not in note:
                    fail(f"{file.name} item {index} is missing '{field}'")

            title = note["title"]
            source_title = note["sourceTitle"]
            summary = note["summary"]
            aliases = note["aliases"]
            chips = note["chips"]
            counterparts = note.get("counterparts", [])
            synonyms = note.get("synonyms", [])
            antonyms = note.get("antonyms", [])
            see_also = note.get("seeAlso", [])
            forms = note.get("forms", [])

            if not isinstance(title, str) or not normalized_lookup_key(title):
                fail(f"{file.name} item {index} has an empty title")
            if not isinstance(source_title, str) or not source_title.strip():
                fail(f"{file.name} item {index} has an empty sourceTitle")
            if not isinstance(summary, str) or len(summary.strip()) < 20:
                fail(f"{file.name} item {index} summary is too short")
            if not isinstance(aliases, list) or not all(isinstance(x, str) for x in aliases):
                fail(f"{file.name} item {index} aliases must be a string array")
            if not isinstance(chips, list) or not all(isinstance(x, str) and x.strip() for x in chips):
                fail(f"{file.name} item {index} chips must be a non-empty string array")
            if not isinstance(counterparts, list):
                fail(f"{file.name} item {index} counterparts must be an array")
            if not isinstance(synonyms, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in synonyms):
                fail(f"{file.name} item {index} synonyms must be a string array")
            if not isinstance(antonyms, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in antonyms):
                fail(f"{file.name} item {index} antonyms must be a string array")
            if not isinstance(see_also, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in see_also):
                fail(f"{file.name} item {index} seeAlso must be a string array")
            if not isinstance(forms, list):
                fail(f"{file.name} item {index} forms must be an array")

            for counterpart_index, counterpart in enumerate(counterparts, start=1):
                if not isinstance(counterpart, dict):
                    fail(f"{file.name} item {index} counterpart {counterpart_index} must be an object")
                label = counterpart.get("label")
                term = counterpart.get("term")
                if not isinstance(label, str) or not label.strip():
                    fail(f"{file.name} item {index} counterpart {counterpart_index} needs a non-empty label")
                if not isinstance(term, str) or not normalized_lookup_key(term):
                    fail(f"{file.name} item {index} counterpart {counterpart_index} needs a non-empty term")

            titles[normalized_lookup_key(title)] += 1
            for lookup in [title] + aliases + synonyms + antonyms:
                key = normalized_lookup_key(lookup)
                if key:
                    lookup_keys[key] += 1
            for target in see_also:
                see_also_refs.append((f"{file.name} item {index}", target))

            for form_index, form in enumerate(forms, start=1):
                if not isinstance(form, dict):
                    fail(f"{file.name} item {index} form {form_index} must be an object")

                for field in ["title", "summary", "aliases", "chips"]:
                    if field not in form:
                        fail(f"{file.name} item {index} form {form_index} is missing '{field}'")

                form_title = form["title"]
                form_summary = form["summary"]
                form_aliases = form["aliases"]
                form_chips = form["chips"]
                form_counterparts = form.get("counterparts", [])
                form_synonyms = form.get("synonyms", [])
                form_antonyms = form.get("antonyms", [])
                form_see_also = form.get("seeAlso", [])

                if not isinstance(form_title, str) or not normalized_lookup_key(form_title):
                    fail(f"{file.name} item {index} form {form_index} has an empty title")
                if not isinstance(form_summary, str) or len(form_summary.strip()) < 20:
                    fail(f"{file.name} item {index} form {form_index} summary is too short")
                if not isinstance(form_aliases, list) or not all(isinstance(x, str) for x in form_aliases):
                    fail(f"{file.name} item {index} form {form_index} aliases must be a string array")
                if not isinstance(form_chips, list) or not all(isinstance(x, str) and x.strip() for x in form_chips):
                    fail(f"{file.name} item {index} form {form_index} chips must be a non-empty string array")
                if not isinstance(form_counterparts, list):
                    fail(f"{file.name} item {index} form {form_index} counterparts must be an array")
                if not isinstance(form_synonyms, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in form_synonyms):
                    fail(f"{file.name} item {index} form {form_index} synonyms must be a string array")
                if not isinstance(form_antonyms, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in form_antonyms):
                    fail(f"{file.name} item {index} form {form_index} antonyms must be a string array")
                if not isinstance(form_see_also, list) or not all(isinstance(x, str) and normalized_lookup_key(x) for x in form_see_also):
                    fail(f"{file.name} item {index} form {form_index} seeAlso must be a string array")

                for counterpart_index, counterpart in enumerate(form_counterparts, start=1):
                    if not isinstance(counterpart, dict):
                        fail(f"{file.name} item {index} form {form_index} counterpart {counterpart_index} must be an object")
                    label = counterpart.get("label")
                    term = counterpart.get("term")
                    if not isinstance(label, str) or not label.strip():
                        fail(f"{file.name} item {index} form {form_index} counterpart {counterpart_index} needs a non-empty label")
                    if not isinstance(term, str) or not normalized_lookup_key(term):
                        fail(f"{file.name} item {index} form {form_index} counterpart {counterpart_index} needs a non-empty term")

                titles[normalized_lookup_key(form_title)] += 1
                for lookup in [form_title] + form_aliases + form_synonyms + form_antonyms:
                    key = normalized_lookup_key(lookup)
                    if key:
                        lookup_keys[key] += 1
                for target in form_see_also:
                    see_also_refs.append((f"{file.name} item {index} form {form_index}", target))

            total_notes += 1

    duplicate_titles = sorted(key for key, count in titles.items() if count > 1)
    if duplicate_titles:
        fail(f"duplicate titles found: {', '.join(duplicate_titles[:10])}")

    missing_see_also = sorted(
        f"{owner} -> {target}"
        for owner, target in see_also_refs
        if normalized_lookup_key(target) not in lookup_keys
    )
    if missing_see_also:
        preview = ", ".join(missing_see_also[:10])
        fail(f"unresolved seeAlso references found: {preview}")

    print(f"reference-notes validation passed: {total_notes} notes across {len(files)} files")
    for file in files:
        payload = json.loads(file.read_text(encoding='utf-8'))
        print(f"  {file.name}: {len(payload)} notes")


if __name__ == "__main__":
    main()
