#!/usr/bin/env python3
"""Build a separate, allowlisted English corpus; never read the evaluation corpus."""
import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
INPUTS = {
    "english-wordnet-2025.xml.gz": ("https://en-word.net/downloads/english-wordnet-2025.xml.gz", "9ca6d1dcb75f822fdd66617f7d9da48142ace38dd544d6ad5e2feca1674ad3fe"),
    "WordNet-3.0.tar.gz": ("https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz", "640db279c949a88f61f851dd54ebbb22d003f8b90b85267042ef85a3781d3a52"),
    "OEWN-LICENSE.txt": ("https://raw.githubusercontent.com/globalwordnet/english-wordnet/main/LICENSE.md", "672cc8b5663e8dc74c4b07a9dcf477193853575b119908fd3dc0aeeb60a9dbbb"),
    "OEWN-WNDB-LICENSE.txt": ("https://raw.githubusercontent.com/globalwordnet/english-wordnet/main/WNDB_License.txt", "df30ec18fbabcdaf031b79ea026d3e6b959010cffe6dd7be9ac137822175b904"),
}

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / "build/public-inputs")
    parser.add_argument("--output", type=Path, default=ROOT / "build/public-core-corpus")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Output already exists; use a fresh directory. Existing corpora are never overwritten.")
    args.cache.mkdir(parents=True, exist_ok=True)
    for name, (url, digest) in INPUTS.items():
        target = args.cache / name
        if not target.exists():
            with urllib.request.urlopen(url, timeout=60) as response, target.open("xb") as out:
                shutil.copyfileobj(response, out)
        if sha(target) != digest:
            raise SystemExit(f"Source checksum mismatch: {name}; stop and review the upstream change.")
    spec = importlib.util.spec_from_file_location("compiler", ROOT / "Scripts/compile-offline-runtime.py")
    compiler = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(compiler)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mongrel-public-core-") as directory:
        work = Path(directory)
        output = work / "corpus"
        output.mkdir()
        xml = work / "wordnet.xml"
        with gzip.open(args.cache / "english-wordnet-2025.xml.gz", "rb") as src, xml.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        classic_paths = []
        with tarfile.open(args.cache / "WordNet-3.0.tar.gz") as archive:
            # Read only named members, never extract paths supplied by the archive.
            for suffix, pos in [("noun", "n"), ("verb", "v"), ("adj", "a"), ("adv", "r")]:
                name = "data." + suffix
                target = work / name
                with archive.extractfile("WordNet-3.0/dict/" + name) as src, target.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                classic_paths.append((suffix, pos, target))
            with archive.extractfile("WordNet-3.0/LICENSE") as src, (output / "WORDNET-LICENSE.txt").open("wb") as dst:
                shutil.copyfileobj(src, dst)
        modern = compiler.build_wordnet_2025(xml)
        classic = compiler.build_wordnet_classic(classic_paths)
        compiler.write_archive(output / "WordNet2025.mgrt", modern)
        compiler.write_archive(output / "WordNetClassic.mgrt", classic)
        headwords = sorted(set(modern["sortedHeadwords"]) | set(classic["sortedHeadwords"]))
        compiler.write_archive(output / "SearchLexicon.mgrt", {"version": 2, "sortedHeadwords": headwords})
        compiler.write_archive(output / "DeepLookupLexicon.mgrt", {"version": 1, "sortedHeadwords": headwords})
        compiler.write_fast_lookup_sqlite(output / "FastLookup.sqlite3", modern)
        rows = []
        for word, synonyms in sorted(classic["synonymsByHeadword"].items()):
            if synonyms:
                rows.append((word, 0, "WordNet 3.0 synonyms", word, ", ".join(synonyms[:28]), json.dumps(["synonyms", "WordNet 3.0"])))
        compiler.write_card_lookup_sqlite(output / "SynonymLookup.sqlite3", "synonym_cards", rows)
        for name in ("OEWN-LICENSE.txt", "OEWN-WNDB-LICENSE.txt"):
            shutil.copy2(args.cache / name, output / name)
        (output / "CORPUS-NOTICES.txt").write_text(
            "Mongrel Dictionary Core Beta — English definitions and related words\n\n"
            "Open English Wordnet 2025, Open English Wordnet team and contributors.\n"
            "Derived from Princeton WordNet; CC BY 4.0 and inherited WordNet notice.\n"
            "Source: https://en-word.net/downloads\n"
            "License: https://creativecommons.org/licenses/by/4.0/\n"
            "Contributors: https://github.com/globalwordnet/english-wordnet/graphs/contributors\n\n"
            "Princeton WordNet 3.0, Copyright 2006 Princeton University.\n"
            "Source: https://wordnet.princeton.edu/\n"
            "Citation: George A. Miller (1995), WordNet: A Lexical Database for English,\n"
            "Communications of the ACM 38(11), 39–41. Christiane Fellbaum (1998, ed.),\n"
            "WordNet: An Electronic Lexical Database, MIT Press.\n\n"
            "Mongrel transforms these datasets into bounded property-list/SQLite indexes,\n"
            "normalizes lookup keys, merges homograph senses, and truncates some display\n"
            "summaries and related-word lists. It is not an unmodified upstream edition.\n"
            "WordNet is a registered trademark. No upstream endorsement is implied.\n"
            "Original data retains its own terms, not Mongrel's PolyForm code license.\n"
            "Full notices: WORDNET-LICENSE.txt, OEWN-LICENSE.txt, OEWN-WNDB-LICENSE.txt.\n\n"
            "This edition excludes the evaluation corpus's translation databases,\n"
            "regional/slang archives, reference notes, OpenOffice and Moby thesauri.\n",
            encoding="utf-8")
        manifest = {
            "edition": "public-core", "version": 1,
            "sources": [{"file": name, "url": url, "sha256": digest} for name, (url, digest) in INPUTS.items()],
            "counts": {"modernHeadwords": len(modern["sortedHeadwords"]), "classicHeadwords": len(classic["sortedHeadwords"]), "searchHeadwords": len(headwords), "synonymHeadwords": len(rows)},
            "files": {path.name: sha(path) for path in sorted(output.iterdir())},
        }
        (output / "PUBLIC-CORPUS.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copytree(output, args.output)
    print(json.dumps(manifest["counts"], indent=2))
    print("Separate public-core corpus prepared:", args.output)

if __name__ == "__main__":
    main()
