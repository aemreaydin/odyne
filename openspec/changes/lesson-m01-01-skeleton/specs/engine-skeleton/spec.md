<!-- Delta spec for the ENGINE capability this lesson builds: the layered package
     skeleton and its build/test workflow. Describes observable behavior, not the
     learner's exact signatures (those are agreed in design.md). Merges into
     openspec/specs/engine-skeleton/ at archive. -->

## ADDED Requirements

### Requirement: Layered package structure
The engine SHALL be organized into the packages `core`, `platform`, `render`, and `game` (one Odin package per directory under `engine/`), addressable through an `engine` import collection. Inter-package imports SHALL point downward only, in the order `core → platform → render → game`; no package SHALL import a package at its own layer or above it.

#### Scenario: Downward import resolves
- **WHEN** `engine/game` imports `engine:render`, `engine:platform`, or `engine:core` (transitively or directly)
- **THEN** the build resolves the import and compiles

#### Scenario: Upward import is rejected
- **WHEN** a lower-layer package (e.g. `core`) imports a higher-layer package (e.g. `platform`) such that a cycle is formed
- **THEN** the Odin compiler rejects the build with a `Cyclic importation` error

### Requirement: Buildable application entry point
The engine SHALL provide an application entry package with a `main` procedure that boots top-down through all four layers and prints a banner identifying each layer. The application SHALL build to an executable using the `engine` collection.

#### Scenario: App builds and boots the stack
- **WHEN** the application package is built with `-collection:engine=engine` and run
- **THEN** an executable is produced and running it prints a boot banner that names `core`, `platform`, `render`, and `game`

### Requirement: Core build information
The `core` package SHALL expose the engine's build/version information through a public surface that is unit-testable in isolation.

#### Scenario: Version reported
- **WHEN** the core build-info surface is queried in a `core:testing` test
- **THEN** it returns the engine's version, matching the declared version constant

### Requirement: Toolchain-gated workflow
Each engine package that has tests SHALL be runnable via `odin test`, and the whole tree SHALL compile clean under `-vet -strict-style`.

#### Scenario: Vet and style are clean
- **WHEN** the engine is built or tested with `-vet -strict-style`
- **THEN** the build completes with no vet or style diagnostics
