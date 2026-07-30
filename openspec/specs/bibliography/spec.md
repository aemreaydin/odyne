# bibliography Specification

## Purpose
Citation discipline. Every factual claim in a lesson or review carries a cite-key registered
in `curriculum/BIBLIOGRAPHY.md`, with the chapter, section or timestamp the source provides.
Covers the registry's entry format, the rule that only registered keys may be cited, the
link-verification required before a new key is registered, and the expected granularity of a
citation.

## Requirements
### Requirement: Cite-key registry
`curriculum/BIBLIOGRAPHY.md` SHALL hold every source the curriculum references, one entry per source, each with: a stable unique cite-key (e.g., `GEA`, `GB-MEM`, `VKGUIDE`), full title, author(s), type (book, article, video, talk, code, docs), URL and/or ISBN, and the date the entry was added or last verified.

#### Scenario: Entry added
- **WHEN** a source is added to the bibliography
- **THEN** the entry contains all required fields and its cite-key is unique

### Requirement: Cite only registered keys
Lesson explanations and reviews MUST cite sources only via cite-keys registered in `BIBLIOGRAPHY.md`. Free-floating links or from-memory references are not citations.

#### Scenario: Unregistered source needed
- **WHEN** the tutor wants to cite a source with no registry entry
- **THEN** the tutor first adds a verified entry to `BIBLIOGRAPHY.md`, then cites its key

### Requirement: Link verification
Web-based entries MUST be verified reachable (via web search or fetch) when added; books MUST carry a real ISBN or publisher page. A factual claim whose source cannot be verified SHALL be marked `[unverified]` in the lesson text rather than silently asserted.

#### Scenario: Adding a web source
- **WHEN** a web source is registered
- **THEN** its URL was confirmed reachable in the same session and the verification date recorded

### Requirement: Citation granularity
Where a source has internal subdivisions (chapters, sections, timestamps), citations SHALL include the subdivision — e.g., `[GEA §6.2]`, `[VKGUIDE ch.2]`, `[ND-FIBERS @14:30]` — so the learner can go directly to the referenced material.

#### Scenario: Citing a book
- **WHEN** a lesson cites a book-type source for a specific claim
- **THEN** the citation includes chapter or section, not just the cite-key

