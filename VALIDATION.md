# Public source verification — 25 September 2026

This record concerns the source-available application snapshot. It does not replace the separate evaluation app's release or corpus validation.

- The 61 imported source/build/branding files match the original checkout and the hashes in SOURCE-PROVENANCE.json. Original Swift application and test code is unchanged from the recorded baseline. New/updated build tooling is listed explicitly in that manifest.
- The clean public checkout builds the actual app and core framework in optimized Release for both arm64 and x86_64. Both executables retain a macOS 14.0 deployment target. The application is built with the existing sandbox/hardened-runtime settings; signing is disabled for source validation.
- **84 selected Release XCTest tests passed**, zero failures, on an Apple Silicon Mac with macOS 27, Xcode 26.4, and Swift 6.3. The test runner reported 2.396 seconds of test execution; that is not build or whole-workflow wall time.
- Tests cover session behavior, lookup request normalization, appearance, reading metrics, and fixture-based reliability, including 10,000 distinct SQLite misses. Full corpus coverage and the three real-corpus reliability tests are excluded from this command and are not claimed to pass in this data-free checkout.
- The initial Release test build failed because the framework lacked Swift testability. The verification script now enables testability only for the native test build. The independent universal app build retains normal Release settings.
- The normal runtime validator rejects the missing corpus, as required. This prevents the release packager from treating the source-only build as a complete Dictionary distribution.
- The PolyForm Perimeter 1.0.1 license was downloaded from its official plain-text URL and kept byte-for-byte unchanged. Source, branding, and third-party data scopes are stated separately.
- Root documentation links, shell syntax, source-file provenance, and the publication file list were checked. Generated outputs, lexical archives, authoring notes, credentials, and private Git history are excluded.

No new public installer, signing, notarization, interactive app launch, migration, spoken VoiceOver pass, or test on another physical Mac is claimed. The installed Beta 5 app and recovery data were preserved. Universal compilation and a CI run are not substitutes for testing on a separate physical Mac.

Run the verification with `MongrelDictionary/Scripts/verify-source.sh`; read DEVELOPMENT.md for exact scope and limitations. GitHub Actions repeats that source-only workflow on public pushes and pull requests.
