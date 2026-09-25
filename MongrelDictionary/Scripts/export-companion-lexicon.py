#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import plistlib
import shutil
from datetime import datetime, timezone
from pathlib import Path


def load_binary_plist(path: Path) -> object:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        trimmed = value.strip()
        if not trimmed or trimmed in seen:
            continue
        seen.add(trimmed)
        output.append(trimmed)
    return output


def load_reference_notes(notes_dir: Path) -> list[dict]:
    notes: list[dict] = []
    for path in sorted(notes_dir.glob("*.json")):
        notes.extend(json.loads(path.read_text(encoding="utf-8")))
    return notes


def expand_reference_entries(notes: list[dict]) -> list[dict]:
    entries: list[dict] = []

    for note in notes:
        base_title = note["title"]
        base_counterparts = note.get("counterparts", [])
        base_synonyms = note.get("synonyms", [])
        base_antonyms = note.get("antonyms", [])
        base_related = note.get("seeAlso", [])

        entries.append(
            {
                "term": base_title,
                "entryKind": "base",
                "summary": note["summary"],
                "aliases": dedupe(note.get("aliases", [])),
                "chips": dedupe(note.get("chips", [])),
                "sourceTitle": note["sourceTitle"],
                "counterparts": base_counterparts,
                "synonyms": dedupe(base_synonyms),
                "antonyms": dedupe(base_antonyms),
                "relatedTerms": dedupe(base_related),
                "baseEntry": "",
            }
        )

        for form in note.get("forms", []):
            entries.append(
                {
                    "term": form["title"],
                    "entryKind": "variant",
                    "summary": form["summary"],
                    "aliases": dedupe(form.get("aliases", [])),
                    "chips": dedupe(note.get("chips", []) + form.get("chips", []) + [f"base: {base_title.lower()}"]),
                    "sourceTitle": note["sourceTitle"],
                    "counterparts": dedupe_counterparts(base_counterparts + form.get("counterparts", [])),
                    "synonyms": dedupe(base_synonyms + form.get("synonyms", [])),
                    "antonyms": dedupe(base_antonyms + form.get("antonyms", [])),
                    "relatedTerms": dedupe([base_title] + base_related + form.get("seeAlso", [])),
                    "baseEntry": base_title,
                }
            )

    return sorted(entries, key=lambda entry: (entry["term"].lower(), entry["entryKind"]))


def dedupe_counterparts(counterparts: list[dict]) -> list[dict]:
    seen: set[tuple[str, str]] = set()
    output: list[dict] = []
    for counterpart in counterparts:
        label = counterpart.get("label", "").strip()
        term = counterpart.get("term", "").strip()
        key = (label, term)
        if not label or not term or key in seen:
            continue
        seen.add(key)
        output.append({"label": label, "term": term})
    return output


def write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_tsv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, dialect="excel-tab")
        writer.writeheader()
        writer.writerows(rows)


def write_structured_entries_tsv(path: Path, entries: list[dict]) -> None:
    fieldnames = [
        "term",
        "entryKind",
        "summary",
        "aliases",
        "chips",
        "sourceTitle",
        "counterparts",
        "synonyms",
        "antonyms",
        "relatedTerms",
        "baseEntry",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, dialect="excel-tab")
        writer.writeheader()
        for entry in entries:
            writer.writerow(
                {
                    "term": entry["term"],
                    "entryKind": entry["entryKind"],
                    "summary": entry["summary"],
                    "aliases": " | ".join(entry["aliases"]),
                    "chips": " | ".join(entry["chips"]),
                    "sourceTitle": entry["sourceTitle"],
                    "counterparts": " | ".join(f'{item["label"]}: {item["term"]}' for item in entry["counterparts"]),
                    "synonyms": " | ".join(entry["synonyms"]),
                    "antonyms": " | ".join(entry["antonyms"]),
                    "relatedTerms": " | ".join(entry["relatedTerms"]),
                    "baseEntry": entry["baseEntry"],
                }
            )


def write_headword_pool_tsv(
    path: Path,
    sorted_headwords: list[str],
    note_terms: set[str],
) -> None:
    fieldnames = [
        "term",
        "inReferenceNotes",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, dialect="excel-tab")
        writer.writeheader()
        for term in sorted_headwords:
            writer.writerow(
                {
                    "term": term,
                    "inReferenceNotes": "yes" if term in note_terms else "no",
                }
            )


def write_lines(path: Path, values: list[str]) -> None:
    path.write_text("\n".join(values) + "\n", encoding="utf-8")


def build_readme(manifest: dict) -> str:
    counts = manifest["counts"]
    return "\n".join(
        [
            "Mongrel Dictionary Companion Package",
            "===================================",
            "",
            "This package mirrors the app's offline reference pool for companion writing tools.",
            "",
            "Counts",
            "------",
            f"- Structured entries: {counts['structuredEntries']}",
            f"- Search headwords: {counts['headwords']}",
            f"- Reference notes: {counts['referenceNotes']}",
            "",
            "Files",
            "-----",
            "- manifest.json",
            "  Build metadata and corpus counts.",
            "- structured_entries.json",
            "  Full structured reference material for app integrations, scripting, or downstream transforms.",
            "- structured_entries.tsv",
            "  Spreadsheet-friendly export of the same structured entries.",
            "- headword_pool.txt",
            "  One headword per line. Useful for custom lookup pools and term pickers.",
            "- headword_pool.tsv",
            "  Spreadsheet-friendly headword list with a flag for whether a term already has a structured reference note.",
            "- spellcheck_dictionary.txt",
            "  Plain newline dictionary for companion apps that support custom spelling imports.",
            "",
            "Suggested use",
            "-------------",
            "- Import spellcheck_dictionary.txt into writing tools that accept plain-word custom dictionaries.",
            "- Use structured_entries.tsv for quick filtering, sorting, and editorial review.",
            "- Use structured_entries.json when a tool needs richer fields like chips, counterparts, and related terms.",
            "",
            "Generated",
            "---------",
            f"- UTC timestamp: {manifest['generatedAtUTC']}",
        ]
    ) + "\n"


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    output_root = project_root / "App" / "Data" / "CompanionExports"
    package_root = output_root / "MongrelDictionaryCompanionPackage"
    archives_root = project_root / "App" / "Data" / "OfflineArchives"
    notes_root = project_root / "ReferenceNotesAuthoring"

    search_lexicon = load_binary_plist(archives_root / "SearchLexicon.mgrt")

    notes = load_reference_notes(notes_root)
    structured_entries = expand_reference_entries(notes)

    sorted_headwords: list[str] = search_lexicon["sortedHeadwords"]
    note_terms = {entry["term"].lower() for entry in structured_entries}

    if package_root.exists():
        shutil.rmtree(package_root)
    package_root.mkdir(parents=True, exist_ok=True)

    manifest = {
        "generatedAtUTC": datetime.now(timezone.utc).isoformat(),
        "packageName": "MongrelDictionaryCompanionPackage",
        "counts": {
            "referenceNotes": len(notes),
            "structuredEntries": len(structured_entries),
            "headwords": len(sorted_headwords),
        },
        "files": [
            "manifest.json",
            "README.txt",
            "structured_entries.json",
            "structured_entries.tsv",
            "headword_pool.txt",
            "headword_pool.tsv",
            "spellcheck_dictionary.txt",
        ],
    }

    write_json(package_root / "manifest.json", manifest)
    (package_root / "README.txt").write_text(build_readme(manifest), encoding="utf-8")
    write_json(package_root / "structured_entries.json", structured_entries)
    write_structured_entries_tsv(package_root / "structured_entries.tsv", structured_entries)
    write_lines(package_root / "headword_pool.txt", sorted_headwords)
    write_lines(package_root / "spellcheck_dictionary.txt", sorted_headwords)
    write_headword_pool_tsv(
        package_root / "headword_pool.tsv",
        sorted_headwords,
        note_terms,
    )

    zip_base = output_root / "MongrelDictionaryCompanionPackage"
    zip_path = Path(shutil.make_archive(str(zip_base), "zip", root_dir=output_root, base_dir=package_root.name))

    print(
        f"exported companion package with {len(structured_entries)} structured entries and "
        f"{len(sorted_headwords)} headwords to {package_root}"
    )
    print(f"zipped companion package to {zip_path}")


if __name__ == "__main__":
    main()
