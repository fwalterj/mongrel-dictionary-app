#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import html
import json
import plistlib
import sqlite3
import time
import unicodedata
import xml.etree.ElementTree as ET
from contextlib import contextmanager
from pathlib import Path


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


def deletion_signatures(term: str) -> list[str]:
    if len(term) < 2:
        return []
    signatures: set[str] = set()
    for index in range(len(term)):
        candidate = (term[:index] + term[index + 1 :]).strip()
        if candidate:
            signatures.add(candidate)
    return sorted(signatures)


def load_word_list(path: Path) -> list[str]:
    headwords: set[str] = set()
    for index, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines()):
        if index == 0:
            continue
        trimmed = raw_line.strip()
        if not trimmed:
            continue
        headword = trimmed.split("/", 1)[0]
        normalized = normalize_lookup_key(headword)
        if normalized:
            headwords.add(normalized)
    return sorted(headwords)


def load_regional_english(paths: list[tuple[str, Path]]) -> tuple[dict[str, list[str]], dict[str, int]]:
    regions_by_headword: dict[str, set[str]] = {}
    region_counts: dict[str, int] = {}
    for label, path in paths:
        headwords = load_word_list(path)
        region_counts[label] = len(headwords)
        for headword in headwords:
            regions_by_headword.setdefault(headword, set()).add(label)
    return (
        {key: sorted(values) for key, values in sorted(regions_by_headword.items())},
        region_counts,
    )


def load_openoffice_thesaurus(path: Path) -> dict[str, list[str]]:
    data = path.read_text(encoding="latin-1")
    lines = data.splitlines()
    result: dict[str, list[str]] = {}
    index = 2
    while index < len(lines):
        head = lines[index].strip()
        if not head:
            index += 1
            continue
        parts = head.split("|", 1)
        if len(parts) != 2:
            index += 1
            continue
        try:
            sense_count = int(parts[1])
        except ValueError:
            index += 1
            continue

        key = normalize_lookup_key(parts[0])
        senses: list[str] = []
        for offset in range(1, sense_count + 1):
            if index + offset >= len(lines):
                break
            sense = lines[index + offset].strip()
            if sense:
                senses.append(sense)
        if key and senses:
            result[key] = senses
        index += sense_count + 1
    return dict(sorted(result.items()))


def load_moby_thesaurus(path: Path) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        parts = [part.strip() for part in raw_line.split(",")]
        if not parts or not parts[0]:
            continue
        key = normalize_lookup_key(parts[0])
        synonyms = [part for part in parts[1:] if part]
        if key and synonyms:
            result[key] = synonyms
    return dict(sorted(result.items()))


def build_headword_archive(entries: dict[str, list[str]]) -> dict[str, object]:
    return {
        "version": 1,
        "headwords": sorted(entries.keys()),
    }


def load_za_mafoko(path: Path) -> list[dict[str, dict[str, str]]]:
    supported_keys = [
        "eng", "afr", "zul", "xho", "ssw", "nbl",
        "tsn", "nso", "sot", "ven", "tso", "ngh",
    ]
    entries: list[dict[str, dict[str, str]]] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        try:
            payload = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        values = {
            key: value.strip()
            for key, value in ((key, payload.get(key, "")) for key in supported_keys)
            if isinstance(value, str) and value.strip()
        }
        if values:
            entries.append({"values": values})
    return entries


def load_reference_note_lookup_keys(path: Path) -> set[str]:
    lookup_keys: set[str] = set()
    for file in sorted(path.glob("*.json")):
        notes = json.loads(file.read_text(encoding="utf-8"))
        for note in notes:
            add_lookup_key(lookup_keys, note.get("title", ""))
            for key in note.get("aliases", []):
                add_lookup_key(lookup_keys, key)
            for key in note.get("synonyms", []):
                add_lookup_key(lookup_keys, key)
            for key in note.get("antonyms", []):
                add_lookup_key(lookup_keys, key)
            for form in note.get("forms", []):
                add_lookup_key(lookup_keys, form.get("title", ""))
                for key in form.get("aliases", []):
                    add_lookup_key(lookup_keys, key)
                for key in form.get("synonyms", []):
                    add_lookup_key(lookup_keys, key)
                for key in form.get("antonyms", []):
                    add_lookup_key(lookup_keys, key)
    return lookup_keys


def add_lookup_key(target: set[str], value: str) -> None:
    normalized = normalize_lookup_key(value)
    if normalized:
        target.add(normalized)


def load_wordnet_xml_headwords(path: Path) -> set[str]:
    headwords: set[str] = set()
    for _, element in ET.iterparse(path, events=("end",)):
        if element.tag.endswith("Lemma"):
            written_form = element.attrib.get("writtenForm", "")
            normalized = normalize_lookup_key(written_form)
            if normalized:
                headwords.add(normalized)
        element.clear()
    return headwords


def build_wordnet_2025(path: Path) -> dict[str, object]:
    synsets_by_headword: dict[str, list[str]] = {}
    pos_by_headword: dict[str, str] = {}
    definition_by_synset: dict[str, str] = {}
    headwords_by_synset: dict[str, list[str]] = {}
    synset_count_by_pos_by_headword: dict[str, dict[str, int]] = {}

    current_headword: str | None = None
    current_pos: str | None = None
    current_synsets: list[str] = []
    current_synset_id: str | None = None
    entry_count = 0
    entry_limit = 200_000

    for event, element in ET.iterparse(path, events=("start", "end")):
        tag = element.tag.rsplit("}", 1)[-1]

        if event == "start":
            if tag == "LexicalEntry":
                current_headword = None
                current_pos = None
                current_synsets = []
            elif tag == "Lemma":
                current_headword = element.attrib.get("writtenForm", "")
                current_pos = element.attrib.get("partOfSpeech", "")
            elif tag == "Sense":
                synset = element.attrib.get("synset", "")
                if synset:
                    current_synsets.append(synset)
            elif tag == "Synset":
                current_synset_id = element.attrib.get("id", "")
            continue

        if tag == "LexicalEntry":
            if current_headword and entry_count < entry_limit:
                trimmed_headword = current_headword.strip()
                key = normalize_lookup_key(current_headword)
                if key:
                    synsets_by_headword[key] = list(current_synsets)
                    for synset in current_synsets:
                        lemmas = headwords_by_synset.setdefault(synset, [])
                        if trimmed_headword and trimmed_headword not in lemmas:
                            lemmas.append(trimmed_headword)
                    if current_pos:
                        pos_by_headword[key] = current_pos
                        pos_map = synset_count_by_pos_by_headword.setdefault(key, {})
                        pos_map[current_pos] = pos_map.get(current_pos, 0) + len(current_synsets)
                    entry_count += 1
        elif tag == "Definition":
            if current_synset_id:
                definition = "".join(element.itertext()).strip()
                if definition:
                    definition_by_synset[current_synset_id] = definition
        elif tag == "Synset":
            current_synset_id = None

        element.clear()

    return {
        "version": 1,
        "synsetsByHeadword": synsets_by_headword,
        "posByHeadword": pos_by_headword,
        "definitionBySynset": definition_by_synset,
        "headwordsBySynset": headwords_by_synset,
        "sortedHeadwords": sorted(synsets_by_headword.keys()),
        "synsetCountByPOSByHeadword": synset_count_by_pos_by_headword,
    }


def load_wordnet_classic_headwords(paths: list[Path]) -> set[str]:
    headwords: set[str] = set()
    for path in paths:
        for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not raw_line or raw_line.startswith("  "):
                continue
            parts = raw_line.split()
            if len(parts) < 6 or parts[1] not in {"n", "v", "a", "s", "r"}:
                continue
            normalized = normalize_lookup_key(parts[0].replace("_", " "))
            if normalized:
                headwords.add(normalized)
    return headwords


def build_search_lexicon(
    notes_dir: Path,
    wordnet_xml_path: Path,
    wordnet_classic_index_paths: list[Path],
    aussie_path: Path,
    regional_paths: list[tuple[str, Path]],
) -> dict[str, object]:
    headwords: set[str] = set()
    headwords.update(load_reference_note_lookup_keys(notes_dir))
    headwords.update(load_wordnet_xml_headwords(wordnet_xml_path))
    headwords.update(load_wordnet_classic_headwords(wordnet_classic_index_paths))
    headwords.update(load_word_list(aussie_path))
    for _, path in regional_paths:
        headwords.update(load_word_list(path))

    sorted_headwords = sorted(headwords)
    return {
        "version": 2,
        "sortedHeadwords": sorted_headwords,
    }


def build_deep_lookup_lexicon(
    notes_dir: Path,
    regional_paths: list[tuple[str, Path]],
) -> dict[str, object]:
    headwords: set[str] = set()
    headwords.update(load_reference_note_lookup_keys(notes_dir))
    for _, path in regional_paths:
        headwords.update(load_word_list(path))

    return {
        "version": 1,
        "sortedHeadwords": sorted(headwords),
    }


def dedupe_preserving_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        normalized = normalize_lookup_key(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(normalized)
    return out


def build_wordnet_classic(data_paths: list[tuple[str, str, Path]]) -> dict[str, object]:
    definitions_by_headword: dict[str, list[str]] = {}
    synonyms_by_headword: dict[str, list[str]] = {}
    sense_count_by_pos_by_headword: dict[str, dict[str, int]] = {}

    for _, pos, path in data_paths:
        data = path.read_text(encoding="utf-8", errors="ignore")
        for raw_line in data.splitlines():
            if not raw_line or raw_line.startswith("  "):
                continue
            if "|" not in raw_line:
                continue

            left, gloss = raw_line.split("|", 1)
            left = left.strip()
            gloss = gloss.strip()
            if not left or not gloss:
                continue

            tokens = left.split()
            if len(tokens) < 5:
                continue

            try:
                word_count = int(tokens[3], 16)
            except ValueError:
                continue
            if word_count <= 0:
                continue

            needed = 4 + (word_count * 2)
            if len(tokens) < needed:
                continue

            words: list[str] = []
            index = 4
            for _ in range(word_count):
                raw_word = tokens[index].replace("_", " ")
                normalized = normalize_lookup_key(raw_word)
                if normalized:
                    words.append(normalized)
                index += 2

            unique_words = dedupe_preserving_order(words)
            if not unique_words:
                continue

            for headword in unique_words:
                defs = definitions_by_headword.setdefault(headword, [])
                if gloss not in defs:
                    defs.append(gloss)
                    if len(defs) > 10:
                        del defs[10:]

                related = [word for word in unique_words if word != headword]
                if related:
                    merged = dedupe_preserving_order(synonyms_by_headword.get(headword, []) + related)
                    synonyms_by_headword[headword] = merged[:64]

                pos_map = sense_count_by_pos_by_headword.setdefault(headword, {})
                pos_map[pos] = pos_map.get(pos, 0) + 1

    sorted_headwords = sorted(definitions_by_headword.keys())
    return {
        "version": 1,
        "definitionsByHeadword": definitions_by_headword,
        "synonymsByHeadword": synonyms_by_headword,
        "sortedHeadwords": sorted_headwords,
        "senseCountByPOSByHeadword": sense_count_by_pos_by_headword,
    }


def display_title_for_headword(headword: str) -> str:
    parts = []
    for part in headword.split(" "):
        if not part:
            continue
        parts.append(part[0].upper() + part[1:])
    return " ".join(parts) if parts else headword


def wordnet_pos_name(pos: str) -> str:
    return {
        "n": "noun",
        "v": "verb",
        "a": "adjective",
        "s": "adjective",
        "r": "adverb",
    }.get(pos, pos)


def build_fast_lookup_archive(wordnet_2025: dict[str, object], wordnet_classic: dict[str, object]) -> dict[str, object]:
    modern_entries_by_headword: dict[str, dict[str, object]] = {}

    synsets_by_headword = wordnet_2025["synsetsByHeadword"]
    definition_by_synset = wordnet_2025["definitionBySynset"]
    headwords_by_synset = wordnet_2025["headwordsBySynset"]
    synset_count_by_pos = wordnet_2025["synsetCountByPOSByHeadword"]

    for headword, synsets in synsets_by_headword.items():
        definitions = [definition_by_synset[synset] for synset in synsets[:2] if synset in definition_by_synset]
        if not definitions:
            continue

        related_lemmas: list[str] = []
        seen: set[str] = set()
        for synset in synsets:
            for lemma in headwords_by_synset.get(synset, []):
                normalized = normalize_lookup_key(lemma)
                if normalized and normalized != headword and normalized not in seen:
                    seen.add(normalized)
                    related_lemmas.append(lemma)

        pos_map = synset_count_by_pos.get(headword, {})
        modern_entries_by_headword[headword] = {
            "definitions": definitions,
            "relatedTerms": related_lemmas[:6],
            "posCounts": pos_map,
            "synsetCount": len(synsets),
            "lemmaCount": len(related_lemmas[:6]) + 1,
        }

    return {
        "version": 3,
        "modernEntriesByHeadword": modern_entries_by_headword,
        "classicEntriesByHeadword": {},
    }


def write_fast_lookup_sqlite(path: Path, wordnet_2025: dict[str, object]) -> None:
    separator = "\u001F"
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    if temp_path.exists():
        temp_path.unlink()

    connection = sqlite3.connect(temp_path)
    try:
        connection.execute("PRAGMA journal_mode=OFF;")
        connection.execute("PRAGMA synchronous=OFF;")
        connection.execute("PRAGMA temp_store=MEMORY;")
        connection.execute(
            """
            CREATE TABLE define_entries (
                headword TEXT PRIMARY KEY,
                definitions_blob TEXT NOT NULL,
                related_terms_blob TEXT NOT NULL,
                pos_counts_blob TEXT NOT NULL,
                synset_count INTEGER NOT NULL,
                lemma_count INTEGER NOT NULL
            ) WITHOUT ROWID;
            """
        )

        synsets_by_headword = wordnet_2025["synsetsByHeadword"]
        definition_by_synset = wordnet_2025["definitionBySynset"]
        headwords_by_synset = wordnet_2025["headwordsBySynset"]
        synset_count_by_pos = wordnet_2025["synsetCountByPOSByHeadword"]

        rows: list[tuple[str, str, str, str, int, int]] = []
        for headword, synsets in synsets_by_headword.items():
            definitions = [definition_by_synset[synset] for synset in synsets[:2] if synset in definition_by_synset]
            if not definitions:
                continue

            related_lemmas: list[str] = []
            seen: set[str] = set()
            for synset in synsets[:4]:
                for lemma in headwords_by_synset.get(synset, [])[:6]:
                    normalized = normalize_lookup_key(lemma)
                    if normalized and normalized != headword and normalized not in seen:
                        seen.add(normalized)
                        related_lemmas.append(lemma)
                    if len(related_lemmas) >= 6:
                        break
                if len(related_lemmas) >= 6:
                    break

            pos_blob = "|".join(
                f"{pos}:{count}"
                for pos, count in sorted(synset_count_by_pos.get(headword, {}).items())
            )
            rows.append(
                (
                    headword,
                    separator.join(definitions),
                    separator.join(related_lemmas[:6]),
                    pos_blob,
                    len(synsets),
                    len(related_lemmas[:6]) + 1,
                )
            )

        connection.executemany(
            """
            INSERT INTO define_entries (
                headword,
                definitions_blob,
                related_terms_blob,
                pos_counts_blob,
                synset_count,
                lemma_count
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.commit()
        connection.execute("VACUUM;")
    finally:
        connection.close()
    temp_path.replace(path)


def freedict_lang_name(code: str) -> str:
    mapping = {
        "eng": "English", "spa": "Spanish", "deu": "German", "fra": "French",
        "ita": "Italian", "por": "Portuguese", "nld": "Dutch", "rus": "Russian",
        "ara": "Arabic", "jpn": "Japanese", "zho": "Chinese", "kor": "Korean",
        "swe": "Swedish", "nor": "Norwegian", "dan": "Danish", "fin": "Finnish",
        "pol": "Polish", "ces": "Czech", "hun": "Hungarian", "tur": "Turkish",
        "lat": "Latin", "ell": "Greek", "heb": "Hebrew", "hin": "Hindi",
        "ben": "Bengali", "vie": "Vietnamese", "tha": "Thai", "ind": "Indonesian",
        "afr": "Afrikaans", "swa": "Swahili", "epo": "Esperanto", "iri": "Irish",
        "wel": "Welsh", "cat": "Catalan", "ron": "Romanian", "bul": "Bulgarian",
        "hrv": "Croatian", "srp": "Serbian", "slk": "Slovak", "slv": "Slovenian",
    }
    return mapping.get(code, code.upper())


def build_synonym_lookup_rows(
    openoffice_entries: dict[str, list[str]],
    moby_entries: dict[str, list[str]],
) -> list[tuple[str, int, str, str, str, str]]:
    rows: list[tuple[str, int, str, str, str, str]] = []
    all_headwords = sorted(set(openoffice_entries.keys()) | set(moby_entries.keys()))
    for headword in all_headwords:
        oo_synonyms = [value for value in openoffice_entries.get(headword, []) if normalize_lookup_key(value) != headword]
        moby_synonyms = [value for value in moby_entries.get(headword, []) if normalize_lookup_key(value) != headword]
        merged = list(dict.fromkeys(oo_synonyms + moby_synonyms))
        if not merged:
            continue

        backing: list[str] = []
        if oo_synonyms:
            backing.append("OpenOffice")
        if moby_synonyms:
            backing.append("Moby")

        summary = ", ".join(merged[:28])
        chips = json.dumps(["synonyms"] + backing, ensure_ascii=False, separators=(",", ":"))
        rows.append((headword, 0, "Synonym digest", headword.capitalize(), summary, chips))

    return rows


def build_translation_lookup_rows(
    repo_root: Path,
    za_mafoko_entries: list[dict[str, dict[str, str]]],
) -> list[tuple[str, int, str, str, str, str]]:
    translations_by_headword: dict[str, list[str]] = {}
    freedict_root = repo_root / "fd-dictionaries-master"
    if freedict_root.exists():
        for directory in sorted(path for path in freedict_root.iterdir() if path.is_dir() and path.name.startswith("eng-")):
            pair_code = directory.name
            target_label = freedict_lang_name(pair_code.split("-")[-1])
            tei_path = directory / f"{pair_code}.tei"
            if not tei_path.exists():
                continue

            for _, elem in ET.iterparse(tei_path, events=("end",)):
                if not str(elem.tag).endswith("entry"):
                    continue

                headword: str | None = None
                quotes: list[str] = []
                for child in elem.iter():
                    tag = str(child.tag).split("}")[-1]
                    text = "".join(child.itertext()).strip()
                    if not text:
                        continue
                    if tag == "orth" and headword is None:
                        normalized = normalize_lookup_key(html.unescape(text))
                        if normalized:
                            headword = normalized
                    elif tag == "quote":
                        quotes.append(html.unescape(text))

                if headword and quotes:
                    chunk = f"{target_label}: {' · '.join(list(dict.fromkeys(quotes))[:8])}"
                    translations_by_headword.setdefault(headword, []).append(chunk)

                elem.clear()

    for entry in za_mafoko_entries:
        values = entry.get("values", {})
        if not values:
            continue
        rendered = " · ".join(
            f"{key.upper()}: {value}"
            for key, value in sorted(values.items())
            if value
        )
        if not rendered:
            continue
        for value in values.values():
            normalized = normalize_lookup_key(value)
            if normalized:
                translations_by_headword.setdefault(normalized, []).append(rendered)

    rows: list[tuple[str, int, str, str, str, str]] = []
    for headword, segments in sorted(translations_by_headword.items()):
        merged_segments = list(dict.fromkeys(segments))
        summary = " | ".join(merged_segments[:8])
        chips = json.dumps(["translation", "bilingual"], ensure_ascii=False, separators=(",", ":"))
        rows.append((headword, 0, "Translation digest", headword.capitalize(), summary, chips))
    return rows


def write_card_lookup_sqlite(
    path: Path,
    table_name: str,
    rows: list[tuple[str, int, str, str, str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    if temp_path.exists():
        temp_path.unlink()

    connection = sqlite3.connect(temp_path)
    try:
        connection.execute("PRAGMA journal_mode=OFF;")
        connection.execute("PRAGMA synchronous=OFF;")
        connection.execute("PRAGMA temp_store=MEMORY;")
        connection.execute(
            f"""
            CREATE TABLE {table_name} (
                headword TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                source TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                chips_json TEXT NOT NULL,
                PRIMARY KEY (headword, ordinal)
            ) WITHOUT ROWID;
            """
        )
        connection.executemany(
            f"""
            INSERT INTO {table_name} (
                headword, ordinal, source, title, summary, chips_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.commit()
        connection.execute("VACUUM;")
    finally:
        connection.close()
    temp_path.replace(path)


def write_archive(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("wb") as handle:
        plistlib.dump(payload, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)
    temp_path.replace(path)


def timed_stage(label: str, operation):
    start = time.perf_counter()
    result = operation()
    elapsed = time.perf_counter() - start
    print(f"[offline-runtime] {label}: {elapsed:.2f}s")
    return result


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


def first_existing(*paths: Path) -> Path:
    for path in paths:
        if path.exists():
            return path
    return paths[0]


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    repo_root = project_root.parent
    output_dir = project_root / "App" / "Data" / "OfflineArchives"
    authoring_notes_dir = project_root / "ReferenceNotesAuthoring"
    lock_path = output_dir / ".compile-offline-runtime.lock"

    with exclusive_lock(lock_path):
        aussie_path = repo_root / "Australian-English-Dictionary-main" / "Source" / "2.5" / "Source" / "dictionaries" / "AussieDic.dic"
        regional_paths = [
            ("American", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (American).dic"),
            ("Australian", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (Australian).dic"),
            ("British", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (British).dic"),
            ("Canadian", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (Canadian).dic"),
            ("New Zealand", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (New Zealand).dic"),
            ("South African", repo_root / "01MAY2026_Resources" / "Dictionaries-master" / "English (South African).dic"),
        ]
        openoffice_path = repo_root / "oo2_th_en_GB" / "th_en_GB_final.dat"
        moby_path = repo_root / "Moby-Project-main" / "Moby Thesaurus II" / "mthesaur.txt"
        za_mafoko_path = repo_root / "za-mafoko-master" / "data" / "combined_all.jsonl"
        wordnet_xml_path = repo_root / "english-wordnet-2025.xml"
        wordnet_classic_index_paths = [
            first_existing(repo_root / "dict" / "index.adj", repo_root / "WordNet-3.0" / "dict" / "index.adj"),
            first_existing(repo_root / "dict" / "index.adv", repo_root / "WordNet-3.0" / "dict" / "index.adv"),
            first_existing(repo_root / "dict" / "index.noun", repo_root / "WordNet-3.0" / "dict" / "index.noun"),
            first_existing(repo_root / "dict" / "index.verb", repo_root / "WordNet-3.0" / "dict" / "index.verb"),
        ]
        wordnet_classic_data_paths = [
            ("data.adj", "a", first_existing(repo_root / "dict" / "data.adj", repo_root / "WordNet-3.0" / "dict" / "data.adj")),
            ("data.adv", "r", first_existing(repo_root / "dict" / "data.adv", repo_root / "WordNet-3.0" / "dict" / "data.adv")),
            ("data.noun", "n", first_existing(repo_root / "dict" / "data.noun", repo_root / "WordNet-3.0" / "dict" / "data.noun")),
            ("data.verb", "v", first_existing(repo_root / "dict" / "data.verb", repo_root / "WordNet-3.0" / "dict" / "data.verb")),
        ]

        aussie_headwords = timed_stage("load Aussie wordlist", lambda: load_word_list(aussie_path))
        regional_english, regional_counts = timed_stage(
            "load regional English",
            lambda: load_regional_english(regional_paths),
        )
        openoffice_entries = timed_stage("load OpenOffice thesaurus", lambda: load_openoffice_thesaurus(openoffice_path))
        moby_entries = timed_stage("load Moby thesaurus", lambda: load_moby_thesaurus(moby_path))
        za_mafoko_entries = timed_stage("load ZA Mafoko", lambda: load_za_mafoko(za_mafoko_path))
        search_lexicon = timed_stage(
            "build search lexicon",
            lambda: build_search_lexicon(
                notes_dir=authoring_notes_dir,
                wordnet_xml_path=wordnet_xml_path,
                wordnet_classic_index_paths=wordnet_classic_index_paths,
                aussie_path=aussie_path,
                regional_paths=regional_paths,
            ),
        )
        deep_lookup_lexicon = timed_stage(
            "build deep lookup lexicon",
            lambda: build_deep_lookup_lexicon(
                notes_dir=authoring_notes_dir,
                regional_paths=regional_paths,
            ),
        )
        wordnet_2025 = timed_stage("build WordNet 2025 archive payload", lambda: build_wordnet_2025(wordnet_xml_path))
        wordnet_classic = timed_stage(
            "build WordNet classic archive payload",
            lambda: build_wordnet_classic(wordnet_classic_data_paths),
        )
        synonym_lookup_rows = timed_stage(
            "build synonym lookup rows",
            lambda: build_synonym_lookup_rows(openoffice_entries, moby_entries),
        )
        translation_lookup_rows = timed_stage(
            "build translation lookup rows",
            lambda: build_translation_lookup_rows(repo_root, za_mafoko_entries),
        )
        timed_stage(
            "write Aussie archive",
            lambda: write_archive(
                output_dir / "AussieDictionary.mgrt",
                {"version": 1, "headwords": aussie_headwords},
            ),
        )
        timed_stage(
            "write regional English archive",
            lambda: write_archive(
                output_dir / "RegionalEnglish.mgrt",
                {
                    "version": 1,
                    "regionsByHeadword": regional_english,
                    "sortedHeadwords": list(regional_english.keys()),
                    "regionCounts": regional_counts,
                },
            ),
        )
        timed_stage(
            "write OpenOffice thesaurus archives",
            lambda: (
                write_archive(output_dir / "OpenOfficeThesaurus.mgrt", {"version": 1, "entries": openoffice_entries}),
                write_archive(output_dir / "OpenOfficeThesaurusHeadwords.mgrt", build_headword_archive(openoffice_entries)),
            ),
        )
        timed_stage(
            "write Moby thesaurus archives",
            lambda: (
                write_archive(output_dir / "MobyThesaurus.mgrt", {"version": 1, "entries": moby_entries}),
                write_archive(output_dir / "MobyThesaurusHeadwords.mgrt", build_headword_archive(moby_entries)),
            ),
        )
        timed_stage(
            "write ZA Mafoko archive",
            lambda: write_archive(
                output_dir / "ZAMafoko.mgrt",
                {"version": 1, "entries": za_mafoko_entries},
            ),
        )
        timed_stage("write WordNet 2025 archive", lambda: write_archive(output_dir / "WordNet2025.mgrt", wordnet_2025))
        timed_stage("write WordNet classic archive", lambda: write_archive(output_dir / "WordNetClassic.mgrt", wordnet_classic))
        timed_stage("write search lexicon archive", lambda: write_archive(output_dir / "SearchLexicon.mgrt", search_lexicon))
        timed_stage("write deep lookup archive", lambda: write_archive(output_dir / "DeepLookupLexicon.mgrt", deep_lookup_lexicon))
        timed_stage("write fast lookup SQLite", lambda: write_fast_lookup_sqlite(output_dir / "FastLookup.sqlite3", wordnet_2025))
        timed_stage(
            "write synonym lookup SQLite",
            lambda: write_card_lookup_sqlite(
                output_dir / "SynonymLookup.sqlite3",
                "synonym_cards",
                synonym_lookup_rows,
            ),
        )
        timed_stage(
            "write translation lookup SQLite",
            lambda: write_card_lookup_sqlite(
                output_dir / "TranslationLookup.sqlite3",
                "translation_cards",
                translation_lookup_rows,
            ),
        )
        fast_lookup_archive = output_dir / "FastLookup.mgrt"
        if fast_lookup_archive.exists():
            fast_lookup_archive.unlink()

        print(
            "compiled offline runtime archives: "
            f"{len(aussie_headwords)} Aussie headwords, "
            f"{len(regional_english)} regional English headwords, "
            f"{len(openoffice_entries)} OpenOffice entries, "
            f"{len(moby_entries)} Moby entries, "
            f"{len(za_mafoko_entries)} ZA Mafoko entries, "
            f"{len(wordnet_2025['sortedHeadwords'])} WordNet 2025 headwords, "
            f"{len(wordnet_classic['sortedHeadwords'])} WordNet classic headwords, "
            f"{len(wordnet_2025['synsetsByHeadword'])} fast-lookup headwords, "
            f"{len(synonym_lookup_rows)} synonym digests, "
            f"{len(translation_lookup_rows)} translation digests, "
            f"{len(search_lexicon['sortedHeadwords'])} lexicon headwords, "
            f"{len(deep_lookup_lexicon['sortedHeadwords'])} deep-lookup headwords"
        )


if __name__ == "__main__":
    main()
