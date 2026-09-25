# From observation to implementation

These examples describe code in this snapshot. They make the decisions inspectable, including the boundaries where an apparently small feature interacts with another one.

## Typing is exploration; history records commitment

**Problem:** a live dictionary can turn every partial word into history, then make a reader clean up the record of merely typing.

**Observation:** the session can distinguish an uncommitted preview from a selected or submitted lookup.

**Decision:** preview while typing; record committed lookups. Return can promote an already-running or already-visible preview instead of repeating the same work. Selecting a suggestion has its own explicit intent.

**Implementation and evidence:** `previewSearch(commit:)`, `promoteInFlightLookupToCommitted()`, and `commitCurrentLookupIfNeeded` in [DictionarySession](MongrelDictionary/App/ViewModels/DictionarySession.swift); the preview, Return, and Recents cases in [session tests](MongrelDictionary/Tests/DictionarySessionStartupTests.swift).

**Boundary:** an exact headword with no longer prefix completion may commit automatically. A prefix such as `cat` while reaching `catalog` must not do so prematurely.

## Saving should act on the word being read

**Problem:** while editing a search, the query can differ from the entry still on screen. Saving the half-written query would contradict the visible object of the action.

**Observation:** the displayed term and composing text are different pieces of state.

**Decision:** Save uses the displayed term while the reader composes another query.

**Implementation and evidence:** `focusedTerm`, `currentTermIsFavorite`, and `toggleFavorite()` in [DictionarySession](MongrelDictionary/App/ViewModels/DictionarySession.swift), with a focused composing/favorite regression in [session tests](MongrelDictionary/Tests/DictionarySessionStartupTests.swift).

## Old work must not take the desk back

**Problem:** suggestions or results from an earlier query can arrive after a newer action, refill a cleared desk, or restore an obsolete hint.

**Observation:** cancellation requests and result application are separate events. A response needs to remain relevant when it is applied.

**Decision:** cancel obsolete work and check request/session revisions before publishing. Retyping an already displayed term clears stale suggestion chrome and cancels a different preview.

**Implementation and evidence:** `queryDidChange()`, suggestion revisions, and search generations in [DictionarySession](MongrelDictionary/App/ViewModels/DictionarySession.swift) and [DictionaryRepository](MongrelDictionary/App/Services/DictionaryRepository.swift). The stale-hint regression holds a preview with a continuation; it does not depend on winning a 20 ms scheduling race.

## Repeated use is part of correctness

**Problem:** a lookup can appear fast in isolation while decoded rows and cached misses accumulate during a long session.

**Observation:** reuse is valuable only within an explicit memory budget, and a cached miss must still allow a later fallback candidate.

**Decision:** bound caches, preserve fallback semantics, and measure repeated work. Keep process-memory measurements separate from latency and cold-start claims.

**Implementation and evidence:** [BoundedLookupCache](MongrelDictionary/App/Core/BoundedLookupCache.swift), SQLite row caches in [DictionaryRepository](MongrelDictionary/App/Services/DictionaryRepository.swift), and [reliability tests](MongrelDictionary/Tests/DictionaryReliabilityTests.swift). Public fixture tests exercise 10,000 distinct misses. Full-corpus soaks require the separately reviewed data and are not part of the public source-only check.

## Appearance is a reading decision

**Problem:** visual identity can reduce legibility when decorative effects become necessary to distinguish controls or read text.

**Decision:** use Contrast with Black as the default and an explicit White option. Keep Classic and Custom optional, scale reading text independently, and respect reduced motion/transparency.

**Implementation and evidence:** [appearance model](MongrelDictionary/App/Core/MongrelAppearanceModel.swift), [design system](MongrelDictionary/App/Design/DictionaryDesignSystem.swift), and [appearance and reading-metric tests](MongrelDictionary/Tests/AppearanceContrastTests.swift). A 21:1 primary text/background pair is a measured property of those colors, not certification of the entire interface.

## An offline app must belong to its package

**Problem:** a developer's machine can conceal missing bundled resources by finding a local corpus checkout. The same installer then fails on someone else's Mac.

**Decision:** normal app lookup resolves its own bundled resources. Explicit test initializers provide fault-injection access; missing and malformed resources must not silently fall back to a developer's workbench.

**Implementation and evidence:** the initializers and resource lookup in [DictionaryRepository](MongrelDictionary/App/Services/DictionaryRepository.swift), plus missing/malformed-bundle tests. The public checkout currently omits the evaluation corpus pending rights review; that limitation is explicit in [development and validation](DEVELOPMENT.md).
