# Mongrel Dictionary

A quiet reference desk for the Mac. Look up a word, follow a connection, and get back to what you were doing.

**Free of charge · Publicly inspectable source · PolyForm Perimeter · macOS 14+**

Mongrel Dictionary brings definitions, synonyms, regional vocabulary, and word-level translations into one reading space. Ordinary lookup uses dictionaries stored on your Mac. There is no account, subscription, or paid feature tier.

## Availability

**The application source is public here. A public installer is not available yet.** The existing evaluation corpus is undergoing a redistribution and attribution review, so its data and old installers are excluded from this checkout. The application code, tests, and build tools are available for inspection and source-only verification.

A separate **Core Beta candidate** is being prepared using Open English Wordnet 2025 and Princeton WordNet 3.0: offline English definitions and synonyms, about **152,000 searchable headwords**. It deliberately excludes the evaluation edition's translation database, dedicated regional/slang collections, and reference notes. This is a narrower edition, not a replacement or a claim that the wider corpus is cleared. The [reproducible corpus recipe and release checks](DEVELOPMENT.md#separate-public-core-candidate) are public; downloadable assets remain pending release review.

The October polish adds a 200-word Saved Shelf without silent eviction, history clearing that survives pending lookups, and complete imported WordNet senses behind readable expand/collapse controls. [Validation](VALIDATION.md) distinguishes verified behavior from remaining release gates.

The app targets macOS 14 and later, with Apple Silicon and Intel builds. The evaluation app has been exercised on Apple Silicon running macOS 27. Physical Intel and macOS 14 testing remain outstanding. A source build without the corpus is not a replacement for a functioning Dictionary installation.

## One app in a body of work

Mongrel explores familiar desktop tools without assuming that useful functionality needs to become a service, account, subscription, or upgrade funnel. Beauty, accessibility, local usefulness, and predictable behavior belong in ordinary utilities.

The suite should be recognizable through its decisions: use context the app already has, preserve the reader's place, keep advanced controls available without permanent clutter, and verify how features interact. These are continuing design obligations. Each app's documentation should say what is implemented and what remains an ambition. Read the [suite philosophy](PHILOSOPHY.md).

## Language consists of distinctions

Dictionary's aim is to make regional English intelligible on its own terms and help readers distinguish related words. The implementation preserves source labels, regional spelling counterparts, separate lookup modes, and linked references where its sources support them. It does not claim complete regional coverage or a comprehensive system of register and intensity labels.

At the desk, you can preview searches while typing, commit a lookup to history with Return, save the word being read, use a compact Quick Lookup window, and look up selected text through macOS Services. Translation is a word and phrase reference, not sentence translation. Coverage varies by source.

Contrast starts with **Black** and offers an explicit **White** option. Adjustable reading text, keyboard commands, visible selection, and reduced-motion/transparency support make reading choices part of the design. Classic and Custom remain optional. See [accessibility and keyboard use](ACCESSIBILITY.md).

## Inspect the thinking

[Design decisions](DESIGN-DECISIONS.md) traces concrete observations through decisions, implementation, and tests: composing text versus the displayed word, preview versus committed history, stale background work, bounded caches, and self-contained resources.

Start with [DictionarySession](MongrelDictionary/App/ViewModels/DictionarySession.swift), [DictionaryRepository](MongrelDictionary/App/Services/DictionaryRepository.swift), and the [tests](MongrelDictionary/Tests). [Development and validation](DEVELOPMENT.md) explains the source map and corpus boundary.

```bash
cd MongrelDictionary
./Scripts/verify-source.sh
```

On a Mac with full Xcode and XcodeGen, this builds optimized universal application source and runs native fixture-based XCTest coverage. It does not package a public installer or establish real-corpus performance.

## Ownership and permitted use

The official app is free for ordinary personal, educational, and professional use. Original code is **source-available under [PolyForm Perimeter 1.0.1](LICENSE), not open source**. It permits use, changes, and distribution for permitted purposes while restricting provision of a competing product as defined in the license. Publishing source does not transfer copyright ownership.

[NOTICE.md](NOTICE.md) defines the license scope. [Brand rights](BRANDING.md) remain separate; third-party materials retain their own terms. [Free use and source licensing](APP-LICENSE.md) explains the distinction without replacing the standard license.

## Privacy and feedback

The current app performs lookups locally and has no app analytics or account service. History, saved words, and preferences stay in local macOS storage. Read [privacy and support](PRIVACY.md) before attaching diagnostic material.

Use the [feedback form](https://github.com/fwalterj/mongrel-dictionary-app/issues/new?template=feedback.yml) for bugs, accessibility problems, and unclear interactions. Include the build, macOS version, Mac model, and a non-private example. [Contribution guidance](CONTRIBUTING.md) explains the expectations for changes.
