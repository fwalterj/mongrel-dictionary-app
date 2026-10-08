# Dictionary validation

## 8 October 2026 — polish and separate Core Beta preparation

- Universal optimized source compilation passed; **87 native Release fixture tests** passed with zero failures. Five Python tooling regressions also passed. The corpus-free GitHub workflow runs these checks without downloading data.
- Reproduced and fixed silent Saved Shelf eviction and pending lookups repopulating cleared history. The shelf now holds 200 words, exposes all entries, and refuses overflow without deleting earlier saves.
- Reproduced and fixed OEWN homographs overwriting earlier senses. Tests preserve noun and verb senses while deduplicating repeated references.
- A separate public-core recipe produced 152,549 distinct searchable headwords from hash-verified OEWN 2025 and WordNet 3.0 inputs, preserving upstream notices. Its strict runtime validator passed. Negative tests reject mixed-in evaluation data, missing licenses, altered data and symlinks.
- Source changes preserve the supplied September icon refresh. The installed evaluation Dictionary and Browser were not replaced.
- **93 native Release tests passed with the public-core corpus**, zero failures, including everyday definitions/synonyms, explicit unsupported-mode messaging, both corpus-dependent consistency tests and the diverse workload. The workload exercises the edition's available modes, not absent Translation/Slang shortcuts.
- Interactive inspection uncovered a second truncation: the fast index stored only two definitions and the renderer capped entries at six. Both limits are removed for WordNet entries; the Core corpus is rebuilt, and a native regression checks all 18 imported senses of “bank” reach the result. Long entries retain the existing collapse/expand controls, with one numbered definition per line in the fast path.
- Three rounds of 1,000 diverse cache-bypassed lookups held test-process physical footprint at approximately 29 MB, with about 0.1 MB growth between first and third rounds. Per-round p95 repository lookup timing was about 0.33–0.39 ms. These are warm repository/XCTest measurements, **not** GUI memory, cold-start latency, or a promise for every query. Another 1,000 repeated mixed lookups and 10,000 fixture misses passed bounded-cache checks.
- Interactive checks exercised search, saving, mode switching, Clear History retaining saved/current words, and Quick Lookup. Core-specific placeholder/help text now states its actual coverage. Returning from Quick Lookup reuses a singleton Reference Desk instead of creating duplicate windows with shared state.
- Developer ID identity and the saved notarization profile are present. An actual signing attempt reached a macOS private-key authorization prompt and was stopped while the owner was away. **No new Developer ID/notarized release is claimed.** Local ad-hoc test packaging is separate from the later authenticated public candidate. Physical Intel/macOS 14 and spoken VoiceOver testing remain outstanding.

## Historical baseline — 25 September 2026

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
