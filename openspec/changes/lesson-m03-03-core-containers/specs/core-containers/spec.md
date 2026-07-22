<!-- Delta spec for the ENGINE capability graduated by this lesson: core-containers.
     Merges into openspec/specs/core-containers/ at archive. Requirements describe observable
     behavior, not specific procedure names, so they hold regardless of surface details agreed
     in design.md. The lesson's tests trace to these scenarios. -->

## ADDED Requirements

### Requirement: Generational handle pool
The engine core layer SHALL provide a generational handle pool container that stores items of a caller-chosen type at fixed capacity, issues opaque handles rather than pointers, and detects handle staleness via per-slot generation counters. Every operation taking a handle SHALL reject invalid handles — zero, stale, retired, out-of-range, or arbitrary garbage — by returning an error value, never by panicking or exhibiting undefined behavior.

#### Scenario: Add issues a resolvable handle
- **WHEN** an item is added to a pool with a free slot
- **THEN** a non-zero handle is returned that resolves to that item's value until the item is removed

#### Scenario: Remove makes the handle stale
- **WHEN** an item is removed via its handle
- **THEN** subsequent resolution attempts with that handle return an invalid-handle error, and a second remove with the same handle is likewise rejected

#### Scenario: Slot reuse cannot be confused with the previous occupant
- **WHEN** a slot whose item was removed is reused by a later add
- **THEN** the new handle differs from every handle previously issued for that slot, and the old handles remain invalid

#### Scenario: Garbage handles are rejected safely
- **WHEN** a handle with an out-of-range index, a mismatched generation, or arbitrary bit patterns is presented
- **THEN** the operation returns an invalid-handle error without panicking

#### Scenario: Exhaustion is reported, not fatal
- **WHEN** an add is attempted while every slot is live or retired
- **THEN** it returns a full-pool error and the zero handle, and the pool recovers normal operation once a slot is freed

### Requirement: Caller-typed handles
The handle pool SHALL be generic over the handle type it issues and accepts, so that each engine system can expose its own `distinct` handle type and cross-system handle confusion is a compile-time error at zero runtime cost. The stored item type SHALL be required, at compile time, to embed a handle field of the pool's handle type, which the pool maintains: adding an item stores the issued handle into it, so every stored item identifies itself. The zero (ZII) value of every conforming handle type SHALL never resolve. A ready-made default handle type SHALL be provided for pools that do not cross a package boundary.

#### Scenario: Distinct handle types instantiate independently
- **WHEN** two pools are instantiated with different distinct handle types
- **THEN** each pool issues and accepts only its own handle type, and both operate correctly side by side

#### Scenario: Stored items identify themselves
- **WHEN** an item is added and later obtained by resolution or iteration
- **THEN** its embedded handle field equals the handle issued at add, regardless of the field's value when the item was passed in

#### Scenario: The zero handle is invalid for every handle type
- **WHEN** the zero value of the pool's handle type is presented to any handle-taking operation
- **THEN** it returns an invalid-handle error

### Requirement: Dense iteration
The handle pool SHALL store live items contiguously so that iteration is a plain slice over exactly the live items, with per-item cost independent of pool occupancy. Removal MAY reorder the dense storage, but SHALL preserve the validity of every other outstanding handle.

#### Scenario: Iteration visits exactly the live items
- **WHEN** the pool's live items are iterated after a mix of adds and removes
- **THEN** exactly the live items are visited, with no holes to skip

#### Scenario: Removal preserves other handles
- **WHEN** an item is removed while other items are live
- **THEN** every other outstanding handle still resolves to its original item's value

### Requirement: Owned fixed-capacity storage
The handle pool SHALL own its storage: allocated at fixed capacity from an explicitly stored allocator at initialization and fully released at destruction, with no reallocation during use. Pointers resolved from handles are loans, invalidated by the next removing or destroying mutation, but never by an add.

#### Scenario: Init and destroy are leak-clean
- **WHEN** a pool is initialized, used, and destroyed under a tracking allocator
- **THEN** no allocations leak and none are freed incorrectly

#### Scenario: Bulk clear empties without releasing memory
- **WHEN** the pool is cleared
- **THEN** every previously issued handle becomes stale, the pool's full capacity is available again, and no memory is released

### Requirement: Core containers layering
The core-containers packages SHALL depend only on the Odin standard library and no higher engine layer, keeping the engine package graph acyclic.

#### Scenario: Core containers build without importing upward
- **WHEN** the engine is built with `-collection:engine=engine`
- **THEN** the containers packages compile without importing `platform`, `render`, or `game`, and the build is acyclic
