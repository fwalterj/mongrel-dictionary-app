# Inspect, build, and verify the source

This checkout contains the existing Swift application, repository/search implementation, session model, views, tests, and build/data-compilation tools. It does **not** contain the private evaluation corpus, reference-note authoring files, signed installers, credentials, or earlier private Git history. The separation concerns redistribution rights and private artifacts; the application algorithms are available for inspection.

## Requirements and one-command verification

Use a Mac with full Xcode selected and [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed. The app's deployment target remains macOS 14. The script checks the active Xcode installation; it does not accept licenses or change the developer directory.

```bash
cd MongrelDictionary
./Scripts/verify-source.sh
```

This builds the actual application and framework in **Release** for **arm64 and x86_64**, verifies both architecture slices, then runs native Release XCTest coverage with isolated repository/SQLite fixtures. Outputs and logs are placed in the ignored `MongrelDictionary/build/source-verification/` directory. Set `MONGREL_SOURCE_BUILD_ROOT` to an absolute path to use another build location.

The source-validation app is unsigned and has no lexical corpus. It is useful for inspecting and building the implementation, **not a usable replacement for the installed dictionary or a public alpha installer**. Cross-compilation is not testing on another physical Mac. Do not install this verification output over a working copy.

## Test scope

The source-only command selects session, lookup-request, appearance, reading-metric, and fixture-based reliability tests. It includes stale-result handling, cancellation, persistence, cached misses, cache bounds, long Unicode entries, malformed SQLite data, and missing resources. The complete test sources are public.

Corpus coverage tests and the three reliability tests that require real lexical data are deliberately excluded from this command. The existing full smoke and benchmark scripts remain available for a checkout with a complete, appropriately licensed runtime. Running an unrestricted `xcodebuild test` or the normal full smoke script in this corpus-free checkout is not expected to pass. A successful source-only check does not establish dictionary coverage, real-corpus performance, signing, notarization, installation, or migration.

## Source map

| Area | Entry point |
| --- | --- |
| Session, focus, history, suggestions and cancellation | [DictionarySession.swift](MongrelDictionary/App/ViewModels/DictionarySession.swift) |
| Offline lookup, source selection, SQLite and bounded caches | [DictionaryRepository.swift](MongrelDictionary/App/Services/DictionaryRepository.swift) |
| App lifecycle, menu commands and persistence flush | [DictionaryApplicationDelegate.swift](MongrelDictionary/App/Integration/DictionaryApplicationDelegate.swift) |
| Reference Desk and Quick Lookup | [Views](MongrelDictionary/App/Views) |
| Appearance and reading behavior | [Core](MongrelDictionary/App/Core), [Design](MongrelDictionary/App/Design) |
| Corpus compilation and packaging | [Scripts](MongrelDictionary/Scripts) |
| Behavioral and workload checks | [Tests](MongrelDictionary/Tests) |

Read [design decisions](DESIGN-DECISIONS.md) for the reasoning behind those boundaries. [SOURCE-PROVENANCE.json](SOURCE-PROVENANCE.json) records the imported snapshot's file hashes; a generated Xcode project reflects the resources actually present in this public checkout.

## Data and release boundary

The evaluation build uses independently licensed WordNet, thesaurus, bilingual, regional, and reference materials. Public distribution requires the exact upstream notices, any required corresponding source, and an established provenance for the reference notes. The current evaluation data is excluded while those items are resolved. Neither Perimeter nor notarization clears that data for redistribution.

The ordinary `build-beta.sh` validates the complete evaluation runtime before packaging. It must fail on a source-only checkout. Public releases record the public source commit and separately identified data inputs. Notarization requires committed authored source; the generated Xcode project is regenerated from `project.yml` and the locally present resources, so its generated resource-list differences are excluded from that clean-source check.

## Separate public-core candidate

The optional Core Beta recipe fetches **only** Open English Wordnet 2025 and Princeton WordNet 3.0 from upstream. Fixed SHA-256 checksums cover every input, including license texts. An upstream change stops the build for review. It does not read the private evaluation corpus. OEWN uses [CC BY 4.0](https://en-word.net/downloads); [Princeton's terms](https://wordnet.princeton.edu/license-and-commercial-use) permit redistribution with their notices. All original notices, attribution, modification information, source URLs and a manifest accompany the transformed data; those data licenses are separate from Perimeter.

Use a **separate source checkout**, not the evaluation checkout. Python 3.10+ is required. From `MongrelDictionary`:

```bash
python3 Scripts/prepare-public-core.py
python3 Scripts/verify-runtime.py --edition public-core --root build/public-core-corpus
# Only in a checkout whose OfflineArchives contains README.md and no corpus:
cp build/public-core-corpus/* App/Data/OfflineArchives/
./Scripts/verify-public-core.sh
```

The builder refuses to overwrite an output directory. Select a fresh `--output` when regenerating. The validator rejects extra evaluation archives, missing notices, changed checksums, symlinks, malformed archives and damaged/incomplete databases. Generated corpus files remain Git-ignored. Source-only verification and its CI job never download them automatically.

The resulting edition has 127,306 modern headwords, 147,806 classic headwords, **152,549 distinct searchable headwords**, and 110,708 synonym rows. These are index counts, not a promise of that many independent definitions. Homographs retain senses across parts of speech. The interface offers Define and Synonyms, explains its exclusions, and exposes corpus notices in Help. No bilingual database, dedicated regional/slang collections, Moby/OpenOffice thesaurus, or reference notes are included.

After review and a source commit, packaging can use existing Keychain credentials:

```bash
./Scripts/build-beta.sh --edition public-core --beta-number 6 \
  --signing-identity 'Developer ID Application: YOUR NAME (TEAMID)' \
  --notary-profile 'YOUR SAVED KEYCHAIN PROFILE' \
  --output /absolute/path/to/a/new/candidate-directory
```

Omit signing/notary options for an ad-hoc local candidate, **not** an authenticated public download. Never put passwords, keys or certificates in this repository. The script signs the nested framework and app, notarizes/staples the app before DMG creation, then signs/notarizes/staples the DMG and checks Gatekeeper. ZIP, DMG, SHA-256 checksums, `BUILD-INFO.txt` and `PUBLIC-CORPUS.json` identify the candidate. Signing does not publish anything.

Core uses `com.mongrel.dictionary.corebeta`, the `mongrel-dictionary-core:` URL scheme, and a distinctly named Services entry. Its preferences and filename are separate from the evaluation app. **Do not replace the fuller installed Dictionary.** Public release of this narrower edition remains a product/release-review decision; preparation does not silently redefine the full Dictionary's coverage.
