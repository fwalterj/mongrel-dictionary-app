# Runtime data intentionally excluded

The public source snapshot does not include the evaluation corpus. See the
repository's DEVELOPMENT.md for source-only compilation and fixture tests.

The application implementation is unchanged. This folder is retained so
XcodeGen can construct the normal framework/resource target. No placeholder
lexicon is presented as a functioning Dictionary release.

The normal release packager must reject this incomplete runtime. Publish a
corpus only after its exact provenance, licenses, required notices, and any
corresponding-source obligations are resolved.
