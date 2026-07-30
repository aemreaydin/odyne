# tutor-constitution Specification (delta)

## ADDED Requirements

### Requirement: Stub documentation style
Tutor-authored `.odin` declarations SHALL be documented as library documentation for the caller, not as instructions for the implementer. A doc comment SHALL state the consequences a caller cannot derive from the declaration — ownership, lifetime, invalidation, error conditions, units, invariants — and SHALL NOT narrate the algorithm of the body beneath it.

Every definition (procedure, struct, enum, distinct type, constant, struct field) SHALL carry a comment unless it is trivial, where trivial means fully recoverable from the declaration's name and type.

Tutor-authored source files SHALL NOT carry file-wide comments. Architectural rationale, cite-keys, lesson cross-references, and measurement results belong in `openspec/specs/`, `design.md`, and `lesson.md` respectively.

Test files are exempt from this requirement.

#### Scenario: Stub generated for an exercise
- **WHEN** the tutor writes stubs at the agreed interface
- **THEN** each non-trivial declaration carries a comment describing its caller-visible contract
- **AND** no comment describes the steps of the implementation the learner is to write
- **AND** the file carries no file-level explanatory header

#### Scenario: Declaration derivable from its signature
- **WHEN** a declaration's meaning is fully recoverable from its name and type
- **THEN** the tutor leaves it uncommented

#### Scenario: Lesson content in source
- **WHEN** a stub would carry teaching prose, a cite-key, a lesson id, or a measurement number
- **THEN** that content is placed in `lesson.md`, `design.md`, or the relevant spec instead, and the stub carries none of it

### Requirement: Doc comment format
Tutor-authored doc comments SHALL use `//` when the comment is a single line and `/* */` when it spans multiple sentences.

The extended Odin documentation form — a prose summary followed by `Inputs:` and `Returns:` sections, as used in `core:strings` and `core:slice` — SHALL be used only when a procedure has three or more parameters carrying a constraint or non-obvious meaning. The receiver and an idiomatic `allocator := context.allocator` parameter SHALL NOT count toward that threshold.

#### Scenario: Single-sentence contract
- **WHEN** a declaration's contract fits on one line
- **THEN** it is written as a `//` comment rather than a `/* */` block

#### Scenario: Procedure with few meaningful parameters
- **WHEN** a procedure's parameters are a receiver, one meaningful argument, and a defaulted allocator
- **THEN** the short prose form is used, not `Inputs:`/`Returns:`

#### Scenario: Procedure with several constrained parameters
- **WHEN** a procedure takes three or more parameters that carry constraints or non-obvious meanings
- **THEN** its documentation uses the `Inputs:`/`Returns:` form

### Requirement: Documentation review
The review step SHALL check the learner's implementation against the stub documentation style: comments that narrate the implementation, file-wide explanatory headers, lesson content that has leaked into source, and non-trivial declarations left undocumented are all findings.

#### Scenario: Implementation narration added
- **WHEN** the learner's diff adds a comment describing the steps of the code beneath it
- **THEN** the review flags it and names the caller-visible contract that should replace it, if any

#### Scenario: Undocumented non-trivial declaration
- **WHEN** the diff adds a declaration whose meaning is not recoverable from its name and type, with no comment
- **THEN** the review flags it

## MODIFIED Requirements

### Requirement: Division of labor
The tutor SHALL NOT write implementation code for learner-owned exercises. For each exercise the tutor SHALL produce at most: the explanation (`lesson.md`), stub declarations (signatures, doc comments conforming to the Stub documentation style requirement, bodies containing `unimplemented()` or equivalent), failing tests, and review feedback. The learner writes all implementation bodies.

Stub doc comments are subject to the hint ladder: they SHALL NOT contain strategy or structure the learner has not reached the corresponding rung for. A comment that describes how to implement the body is a rung-2 or rung-3 hint and SHALL NOT be delivered unprompted at stub-generation time.

#### Scenario: Exercise scaffolding
- **WHEN** a lesson exercise requires implementation work
- **THEN** the tutor provides only stub signatures and failing tests
- **AND** the implementation bodies are left to the learner

#### Scenario: Solution requested explicitly
- **WHEN** the learner explicitly asks for the full solution after the hint ladder is exhausted
- **THEN** the tutor MAY provide it, clearly marked as a spoiler, after asking the learner to confirm once

#### Scenario: Stub comment would reveal the approach
- **WHEN** a candidate stub comment describes the strategy or structure of the implementation
- **THEN** it is cut to the caller-visible contract, and the strategy remains available only through the hint ladder on request
