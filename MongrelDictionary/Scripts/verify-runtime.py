#!/usr/bin/env python3
"""Validate the bundled corpus without requiring the untracked authoring inputs."""
from pathlib import Path
import sqlite3
import plistlib
import argparse
import hashlib
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--edition", choices=["evaluation", "public-core"], default="evaluation")
parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1] / "App/Data/OfflineArchives")
args = parser.parse_args()
root = args.root
if args.edition == "public-core":
    expected = {"WordNet2025.mgrt", "WordNetClassic.mgrt", "SearchLexicon.mgrt", "DeepLookupLexicon.mgrt", "FastLookup.sqlite3", "SynonymLookup.sqlite3", "WORDNET-LICENSE.txt", "OEWN-LICENSE.txt", "OEWN-WNDB-LICENSE.txt", "CORPUS-NOTICES.txt"}
    manifest = json.loads((root / "PUBLIC-CORPUS.json").read_text())
    if manifest.get("edition") != "public-core" or manifest.get("version") != 1 or set(manifest.get("files", {})) != expected:
        raise SystemExit("Unrecognized public corpus manifest")
    actual = {p.name for p in root.iterdir()} - {"README.md", "PUBLIC-CORPUS.json"}
    if actual != expected:
        raise SystemExit("Unexpected or missing public corpus files; never mix evaluation archives into this edition")
    for name in sorted(expected):
        path = root / name
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != manifest["files"][name]:
            raise SystemExit(f"Public corpus checksum mismatch: {name}")
        if path.suffix == ".mgrt":
            with path.open("rb") as stream:
                data = plistlib.load(stream)
            if not data.get("version"):
                raise SystemExit(f"Missing archive version: {name}")
    for name, table in [("FastLookup.sqlite3", "define_entries"), ("SynonymLookup.sqlite3", "synonym_cards")]:
        with sqlite3.connect((root / name).resolve().as_uri() + "?mode=ro&immutable=1", uri=True) as connection:
            if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)] or connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0] < 100000:
                raise SystemExit(f"Incomplete or damaged public database: {name}")
    print("Public-core allowlist, checksums, archive parsing and SQLite checks passed.")
    raise SystemExit(0)

if (root / "PUBLIC-CORPUS.json").exists():
    raise SystemExit("This is a public-core corpus; select --edition public-core explicitly.")
archives = (
    "AussieDictionary", "DeepLookupLexicon", "MobyThesaurus",
    "MobyThesaurusHeadwords", "OpenOfficeThesaurus", "OpenOfficeThesaurusHeadwords",
    "ReferenceNotes", "RegionalEnglish", "SearchLexicon", "WordNet2025",
    "WordNetClassic", "ZAMafoko",
)
for name in archives:
    path = root / f"{name}.mgrt"
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"Missing runtime archive: {path}. Full runtime data is required; source-only checkouts deliberately exclude it. See the development or distribution documentation.")
    try:
        with path.open("rb") as stream:
            plistlib.load(stream)
    except Exception as error:
        raise SystemExit(f"Malformed runtime archive: {path}: {error}")

for name in ("FastLookup", "ReferenceNotes", "SynonymLookup", "TranslationLookup"):
    path = root / f"{name}.sqlite3"
    if not path.is_file():
        raise SystemExit(f"Missing runtime database: {path}. Full runtime data is required; source-only checkouts deliberately exclude it. See the development or distribution documentation.")
    connection = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)
    try:
        result = connection.execute("PRAGMA quick_check").fetchall()
        if result != [("ok",)]:
            raise SystemExit(f"Runtime integrity check failed: {path}: {result}")
    finally:
        connection.close()
print("Runtime archives present; all four SQLite integrity checks passed.")
