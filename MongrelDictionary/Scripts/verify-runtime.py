#!/usr/bin/env python3
"""Validate the bundled corpus without requiring the untracked authoring inputs."""
from pathlib import Path
import sqlite3
import plistlib

root = Path(__file__).resolve().parents[1] / "App/Data/OfflineArchives"
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
