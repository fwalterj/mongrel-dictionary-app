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

The ordinary `build-beta.sh` validates the complete runtime before packaging. It must fail on this source-only checkout. A later public corpus must be identified, licensed, bundled, tested, and packaged as a new release before this repository offers a DMG or ZIP. Public releases should record the exact public source commit and any separately identified data inputs.
