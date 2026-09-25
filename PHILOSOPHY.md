# Mongrel: software should occasionally just be a tool

Mongrel is a body of work about familiar desktop tasks. The aim is to make ordinary utilities pleasant, capable, and dependable without turning each useful action into an account, subscription, ecosystem, or upgrade funnel.

Official Mongrel apps are free to use. Public source makes their implementation and reasoning inspectable. Ownership is retained, and each repository states its own license. Original Dictionary code uses PolyForm Perimeter; that choice does not override another application's license or an upstream component's terms.

## House rules

1. Ordinary utility should not require recurring rent.
2. Obvious functionality should not be withheld to manufacture a paid tier.
3. Use context the application already has before asking the user to supply it again.
4. Preserve the user's place, selection, and working context wherever the action allows it.
5. Keep advanced capability available without making every advanced control permanent.
6. Prefer ordinary files and formats that remain useful outside the suite.
7. Design tools to remain useful without the developer operating a service.
8. Verify the intersections between features: focus, selection, punctuation, geometry, persistence, cancellation, and recovery are part of the feature.

These are decision rules and continuing obligations, not a claim that every application already satisfies every rule. Product pages and validation records should distinguish implementation, tested behavior, limitations, and ambitions.

## A shared interaction vocabulary

The suite should teach habits that transfer between applications: change reading scale while preserving context, use Escape to return to the primary task, keep search from gratuitously rearranging the workspace, make paste sensitive to its destination, restore useful state after reopening, and group undo around actions a person recognizes.

An individual app must document which of those behaviors it actually implements. Dictionary currently has adjustable reading text, local session restoration, committed lookup history, contextual saving of the displayed word, and explicit protection against stale search work. A suite-wide promise of viewport anchoring, universal Escape behavior, cross-Mac synchronization, or semantic paste is not established by this repository.

## Dictionary's contribution

Language consists of distinctions. Regional English should be understandable on its own terms, not presented as a list of mistakes against a single national default. A thesaurus should help a reader choose a word, with attention to meaning and usage rather than treating every related word as interchangeable.

The current implementation carries source labels, regional spelling counterparts, separate lookup intents, and linked references where its sources support them. Fine-grained register, intensity, datedness, and regional-sense labels remain dependent on available evidence; this statement does not announce a new semantic annotation system.

The [design decisions](DESIGN-DECISIONS.md) show how this philosophy becomes concrete behavior in Dictionary's existing source and tests. Similar reasoning, expressed differently for writing, calculating, browsing, or playing media, is what should make the suite recognizable.
