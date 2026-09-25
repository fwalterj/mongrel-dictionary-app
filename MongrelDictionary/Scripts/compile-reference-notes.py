#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import json
import plistlib
import sqlite3
import unicodedata
from contextlib import contextmanager
from pathlib import Path

IGNORED_TOPIC_CHIPS = {
    "adjective",
    "adverb",
    "american english",
    "american politics",
    "australian english",
    "british english",
    "canadian english",
    "colloquial",
    "commonwealth",
    "cross-dialect",
    "culture",
    "dialect",
    "etymology",
    "everyday speech",
    "figurative use",
    "historical",
    "informal",
    "irish english",
    "new zealand english",
    "noun",
    "participle",
    "plural",
    "plural form",
    "regional usage",
    "scots",
    "south african english",
    "spelling",
    "usage note",
    "variant entry",
    "variant spelling",
    "word origins",
}


@contextmanager
def exclusive_lock(lock_path: Path):
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    try:
        lock_path.unlink()
    except FileNotFoundError:
        pass

PHRASE_CORE_STOPWORDS = {
    "a",
    "an",
    "the",
    "of",
    "in",
    "to",
    "for",
    "at",
    "my",
    "your",
    "his",
    "her",
    "our",
    "their",
    "ones",
    "someone",
    "someones",
    "somebody",
    "somebodys",
}


def normalize_lookup_key(value: str) -> str:
    normalized = (
        value.strip()
        .replace("\u00A0", " ")
        .replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u201B", "'")
        .replace("\u2010", "-")
        .replace("\u2011", "-")
        .replace("\u2012", "-")
        .replace("\u2013", "-")
        .replace("\u2014", "-")
    )
    normalized = (
        unicodedata.normalize("NFKD", normalized)
        .encode("ascii", "ignore")
        .decode("ascii")
        .lower()
    )
    return " ".join(part for part in normalized.split() if part)


def phrase_core_lookup_key(value: str) -> str:
    normalized = normalize_lookup_key(value)
    if " " not in normalized and "-" not in normalized and "'" not in normalized:
        return normalized

    tokenized = (
        normalized.replace("-", " ").replace("'", "").split()
    )
    return " ".join(token for token in tokenized if token and token not in PHRASE_CORE_STOPWORDS)


def dedupe_strings(values: list[str]) -> list[str]:
    seen: set[str] = set()
    output: list[str] = []
    for value in values:
        trimmed = value.strip()
        if not trimmed:
            continue
        key = normalize_lookup_key(trimmed)
        if not key or key in seen:
            continue
        seen.add(key)
        output.append(trimmed)
    return output


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


def semantic_topic_chips(chips: list[str]) -> set[str]:
    topics: set[str] = set()
    for chip in chips:
        normalized = normalize_lookup_key(chip)
        if not normalized or normalized in IGNORED_TOPIC_CHIPS or normalized.startswith("base:"):
            continue
        topics.add(normalized)
    return topics


def reference_entry_cache_key(entry: dict) -> str:
    return f"{normalize_lookup_key(entry['title'])}::{normalize_lookup_key(entry['sourceTitle'])}"


def expand_entries(notes: list[dict]) -> list[dict]:
    entries: list[dict] = []

    for note in notes:
        title = note["title"]
        aliases = dedupe_strings(note.get("aliases", []))
        chips = dedupe_strings(note.get("chips", []))
        counterparts = dedupe_counterparts(note.get("counterparts", []))
        synonyms = dedupe_strings(note.get("synonyms", []))
        antonyms = dedupe_strings(note.get("antonyms", []))
        see_also = dedupe_strings(note.get("seeAlso", []))

        entries.append(
            {
                "title": title,
                "sourceTitle": note["sourceTitle"],
                "summary": note["summary"],
                "aliases": aliases,
                "chips": chips,
                "counterparts": counterparts,
                "synonyms": synonyms,
                "antonyms": antonyms,
                "seeAlso": see_also,
                "lookupKeys": [title] + aliases + synonyms + antonyms,
                "isVariant": False,
            }
        )

        for form in note.get("forms", []):
            form_aliases = dedupe_strings(form.get("aliases", []))
            form_chips = dedupe_strings(chips + form.get("chips", []) + ["variant entry", f"base: {title.lower()}"])
            form_counterparts = dedupe_counterparts(counterparts + form.get("counterparts", []))
            form_synonyms = dedupe_strings(synonyms + form.get("synonyms", []))
            form_antonyms = dedupe_strings(antonyms + form.get("antonyms", []))
            form_see_also = dedupe_strings([title] + see_also + form.get("seeAlso", []))
            entries.append(
                {
                    "title": form["title"],
                    "sourceTitle": note["sourceTitle"],
                    "summary": form["summary"],
                    "aliases": form_aliases,
                    "chips": form_chips,
                    "counterparts": form_counterparts,
                    "synonyms": form_synonyms,
                    "antonyms": form_antonyms,
                    "seeAlso": form_see_also,
                    "lookupKeys": [form["title"]] + form_aliases + form_synonyms + form_antonyms,
                    "isVariant": True,
                }
            )

    return entries


def topic_mesh_terms(
    entry: dict,
    entries: list[dict],
    semantic_topics_by_entry_key: dict[str, set[str]],
    excluded_keys: set[str],
) -> list[str]:
    source_topics = semantic_topics_by_entry_key.get(reference_entry_cache_key(entry), set())
    if not source_topics:
        return []

    scored: list[tuple[int, str]] = []
    entry_title_key = normalize_lookup_key(entry["title"])
    entry_source_key = normalize_lookup_key(entry["sourceTitle"])

    for candidate in entries:
        candidate_key = normalize_lookup_key(candidate["title"])
        if candidate_key == entry_title_key or candidate_key in excluded_keys:
            continue

        candidate_topics = semantic_topics_by_entry_key.get(reference_entry_cache_key(candidate), set())
        shared_topics = source_topics.intersection(candidate_topics)
        if not shared_topics:
            continue

        score = len(shared_topics) * 100
        if not candidate["isVariant"]:
            score += 8
        if normalize_lookup_key(candidate["sourceTitle"]) != entry_source_key:
            score += 6
        if any(normalize_lookup_key(chip) in source_topics for chip in candidate["chips"]):
            score += 4
        scored.append((score, candidate["title"]))

    scored.sort(key=lambda item: (-item[0], item[1]))
    return dedupe_strings([term for _, term in scored[:5]])


def build_archive(notes: list[dict]) -> dict:
    entries = expand_entries(notes)

    entries_by_lookup_key: dict[str, list[dict]] = {}
    entries_by_phrase_core_key: dict[str, list[dict]] = {}
    for entry in entries:
        for key in entry["lookupKeys"]:
            normalized = normalize_lookup_key(key)
            if not normalized:
                continue
            entries_by_lookup_key.setdefault(normalized, []).append(entry)

            phrase_core = phrase_core_lookup_key(key)
            if phrase_core and phrase_core != normalized:
                entries_by_phrase_core_key.setdefault(phrase_core, []).append(entry)

    resolvable_lookup_keys = set(entries_by_lookup_key.keys())
    semantic_topics_by_entry_key = {
        reference_entry_cache_key(entry): semantic_topic_chips(entry["chips"])
        for entry in entries
    }

    topic_terms_by_entry_key: dict[str, list[str]] = {}
    for entry in entries:
        related_terms = [
            related
            for related in dedupe_strings(entry["seeAlso"])
            if normalize_lookup_key(related) != normalize_lookup_key(entry["title"])
            and normalize_lookup_key(related) in resolvable_lookup_keys
        ]
        excluded_topic_terms = {
            normalize_lookup_key(term)
            for term in [entry["title"], *related_terms, *(counterpart["term"] for counterpart in entry["counterparts"])]
            if normalize_lookup_key(term)
        }
        topic_terms_by_entry_key[reference_entry_cache_key(entry)] = topic_mesh_terms(
            entry,
            entries,
            semantic_topics_by_entry_key,
            excluded_topic_terms,
        )

    return {
        "version": 2,
        "notes": notes,
        "entries": entries,
        "entriesByLookupKey": entries_by_lookup_key,
        "entriesByPhraseCoreKey": entries_by_phrase_core_key,
        "sortedHeadwords": sorted(normalize_lookup_key(entry["title"]) for entry in entries),
        "topicTermsByEntryKey": topic_terms_by_entry_key,
        "sourceTitles": sorted({entry["sourceTitle"] for entry in entries}),
    }


def write_plist_atomic(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("wb") as handle:
        plistlib.dump(payload, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)
    temp_path.replace(path)


def write_reference_notes_sqlite(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    if temp_path.exists():
        temp_path.unlink()

    connection = sqlite3.connect(temp_path)
    try:
        connection.execute("PRAGMA journal_mode = DELETE;")
        connection.execute("PRAGMA synchronous = OFF;")
        connection.execute("PRAGMA temp_store = MEMORY;")
        connection.execute("PRAGMA locking_mode = EXCLUSIVE;")
        connection.executescript(
            """
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;

            CREATE TABLE entries (
                entry_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                normalized_title TEXT NOT NULL,
                source_title TEXT NOT NULL,
                entry_json TEXT NOT NULL,
                topic_terms_json TEXT NOT NULL
            ) WITHOUT ROWID;

            CREATE TABLE lookup_map (
                lookup_key TEXT NOT NULL,
                entry_id TEXT NOT NULL,
                PRIMARY KEY (lookup_key, entry_id)
            ) WITHOUT ROWID;

            CREATE TABLE phrase_core_map (
                phrase_core_key TEXT NOT NULL,
                entry_id TEXT NOT NULL,
                PRIMARY KEY (phrase_core_key, entry_id)
            ) WITHOUT ROWID;
            """
        )

        entry_rows: list[tuple[str, str, str, str, str, str]] = []
        lookup_rows: list[tuple[str, str]] = []
        phrase_rows: list[tuple[str, str]] = []

        for entry in payload["entries"]:
            entry_id = reference_entry_cache_key(entry)
            normalized_title = normalize_lookup_key(entry["title"])
            entry_rows.append(
                (
                    entry_id,
                    entry["title"],
                    normalized_title,
                    entry["sourceTitle"],
                    json.dumps(entry, ensure_ascii=False, separators=(",", ":")),
                    json.dumps(payload["topicTermsByEntryKey"].get(entry_id, []), ensure_ascii=False, separators=(",", ":")),
                )
            )

            for key in entry["lookupKeys"]:
                normalized = normalize_lookup_key(key)
                if normalized:
                    lookup_rows.append((normalized, entry_id))

                phrase_core = phrase_core_lookup_key(key)
                if phrase_core and phrase_core != normalized:
                    phrase_rows.append((phrase_core, entry_id))

        connection.executemany(
            """
            INSERT INTO entries (
                entry_id,
                title,
                normalized_title,
                source_title,
                entry_json,
                topic_terms_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            entry_rows,
        )
        connection.executemany(
            "INSERT OR IGNORE INTO lookup_map (lookup_key, entry_id) VALUES (?, ?)",
            lookup_rows,
        )
        connection.executemany(
            "INSERT OR IGNORE INTO phrase_core_map (phrase_core_key, entry_id) VALUES (?, ?)",
            phrase_rows,
        )
        connection.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?)",
            ("source_titles_json", json.dumps(payload["sourceTitles"], ensure_ascii=False, separators=(",", ":"))),
        )
        connection.commit()
        connection.execute("VACUUM;")
    finally:
        connection.close()

    temp_path.replace(path)


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    notes_dir = project_root / "ReferenceNotesAuthoring"
    output_path = project_root / "App" / "Data" / "OfflineArchives" / "ReferenceNotes.mgrt"
    sqlite_output_path = project_root / "App" / "Data" / "OfflineArchives" / "ReferenceNotes.sqlite3"
    lock_path = output_path.parent / ".compile-reference-notes.lock"

    with exclusive_lock(lock_path):
        files = sorted(notes_dir.glob("*.json"))
        notes: list[dict] = []
        for file in files:
            notes.extend(json.loads(file.read_text(encoding="utf-8")))

        payload = build_archive(notes)

        write_plist_atomic(output_path, payload)
        write_reference_notes_sqlite(sqlite_output_path, payload)

        print(
            f"compiled {len(payload['notes'])} notes, "
            f"{len(payload['entries'])} searchable entries to {output_path} "
            f"and {sqlite_output_path}"
        )


if __name__ == "__main__":
    main()
