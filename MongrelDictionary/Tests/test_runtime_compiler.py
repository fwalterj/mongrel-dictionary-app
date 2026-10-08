import importlib.util
from pathlib import Path
import tempfile
import unittest
import hashlib
import json
import subprocess
import sys

spec = importlib.util.spec_from_file_location("compiler", Path(__file__).resolve().parents[1] / "Scripts/compile-offline-runtime.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class RuntimeCompilerTests(unittest.TestCase):
    def test_public_validator_rejects_mixed_private_archives(self):
        self.assert_public_rejected("extra", "Unexpected or missing")

    def test_public_validator_rejects_missing_license(self):
        self.assert_public_rejected("missing", "Unexpected or missing")

    def test_public_validator_rejects_changed_content(self):
        self.assert_public_rejected("changed", "checksum mismatch")

    def test_public_validator_rejects_symlinks(self):
        self.assert_public_rejected("symlink", "checksum mismatch")

    def assert_public_rejected(self, defect, message):
        names = ["WordNet2025.mgrt", "WordNetClassic.mgrt", "SearchLexicon.mgrt",
                 "DeepLookupLexicon.mgrt", "FastLookup.sqlite3", "SynonymLookup.sqlite3",
                 "WORDNET-LICENSE.txt", "OEWN-LICENSE.txt", "OEWN-WNDB-LICENSE.txt", "CORPUS-NOTICES.txt"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in names:
                (root / name).write_bytes(b"fixture")
            digest = hashlib.sha256(b"fixture").hexdigest()
            (root / "PUBLIC-CORPUS.json").write_text(json.dumps({
                "edition": "public-core", "version": 1, "files": dict.fromkeys(names, digest)}))
            if defect == "extra":
                (root / "ReferenceNotes.mgrt").write_bytes(b"must not ship")
            elif defect == "missing":
                (root / "WORDNET-LICENSE.txt").unlink()
            elif defect == "changed":
                (root / "CORPUS-NOTICES.txt").write_bytes(b"altered")
            else:
                (root / "CORPUS-NOTICES.txt").unlink()
                (root / "CORPUS-NOTICES.txt").symlink_to(root / "WORDNET-LICENSE.txt")
            result = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "Scripts/verify-runtime.py"),
                                     "--edition", "public-core", "--root", str(root)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_homographs_preserve_senses_across_parts_of_speech(self):
        xml = '''<LexicalResource><Lexicon>
        <LexicalEntry id="bank-n"><Lemma writtenForm="bank" partOfSpeech="n"/><Sense synset="noun"/></LexicalEntry>
        <LexicalEntry id="bank-v"><Lemma writtenForm="bank" partOfSpeech="v"/><Sense synset="verb"/></LexicalEntry>
        <LexicalEntry id="bank-extra"><Lemma writtenForm="bank" partOfSpeech="n"/><Sense synset="noun"/><Sense synset="river"/></LexicalEntry>
        <Synset id="noun"><Definition>A financial institution.</Definition></Synset>
        <Synset id="verb"><Definition>To tilt an aircraft.</Definition></Synset>
        <Synset id="river"><Definition>The edge of a river.</Definition></Synset>
        </Lexicon></LexicalResource>'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.xml"
            path.write_text(xml)
            archive = compiler.build_wordnet_2025(path)
        self.assertEqual(archive["synsetsByHeadword"]["bank"], ["noun", "verb", "river"])
        self.assertEqual(archive["synsetCountByPOSByHeadword"]["bank"], {"n": 2, "v": 1})
        self.assertEqual(len(archive["sortedHeadwords"]), 1)


if __name__ == "__main__":
    unittest.main()
