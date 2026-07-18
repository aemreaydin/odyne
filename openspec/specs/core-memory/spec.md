# core-memory Specification

## Purpose
TBD - created by archiving change lesson-m02-04-core-memory. Update Purpose after archive.
## Requirements
### Requirement: Arena allocator
The engine core layer SHALL provide an arena (bump) allocator that conforms to the Odin `Allocator` interface, operates over a caller-provided fixed backing buffer it does not own, allocates by advancing a single offset, and reclaims all outstanding allocations at once by reset. It SHALL NOT free individual allocations.

#### Scenario: Allocation advances and zeroes
- **WHEN** an aligned allocation of N bytes is requested from an arena with room
- **THEN** it returns an N-byte, correctly aligned, zeroed region drawn from the backing buffer

#### Scenario: Bulk reset reclaims everything
- **WHEN** the arena is reset (free-all)
- **THEN** all previously allocated memory becomes available again in a single operation

#### Scenario: Exhaustion is reported, not fatal
- **WHEN** an allocation cannot fit in the remaining backing buffer
- **THEN** the arena returns an `.Out_Of_Memory` allocator error and no memory

### Requirement: Pool allocator
The engine core layer SHALL provide a pool (fixed-size block) allocator that conforms to the Odin `Allocator` interface, operates over a caller-provided fixed backing buffer it does not own, and supports O(1) allocation and O(1) freeing of individual blocks via an intrusive free list, with fixed block size set at initialization.

#### Scenario: Allocate, free, and reuse a block
- **WHEN** a block is allocated, freed, and then another block is allocated
- **THEN** the second allocation reuses the freed block's storage

#### Scenario: Exhaustion versus oversize are distinct errors
- **WHEN** an allocation is requested from an empty pool
- **THEN** it returns `.Out_Of_Memory`
- **WHEN** an allocation larger than the pool's block size is requested
- **THEN** it returns `.Invalid_Argument`

#### Scenario: Bulk reset returns every block
- **WHEN** the pool is reset (free-all)
- **THEN** every block, including previously allocated ones, becomes free again

### Requirement: Allocator interface conformance
Both core allocators SHALL be assignable to `context.allocator` such that the built-in `new`, `make`, and `free` operations route through them with no call-site changes.

#### Scenario: Standard allocation builtins route through a core allocator
- **WHEN** `context.allocator` is set to a core arena or pool and `new`/`make` is called
- **THEN** the allocation is served from that allocator's backing buffer

### Requirement: Logging allocator
The engine core layer SHALL provide a logging allocator that wraps any other allocator, forwards every operation to it faithfully (identical result and error), and emits a human-readable trace of each operation (mode, size, alignment, caller location, result). It SHALL keep no allocation state of its own and SHALL NOT alter the wrapped allocator's behavior.

#### Scenario: Wrapped allocations are transparent
- **WHEN** an allocation is made through a logging allocator that wraps a backing allocator
- **THEN** it is served from the backing allocator with the same result and error as calling the backing allocator directly

### Requirement: Core layering
The core-memory allocators SHALL depend only on the Odin standard library (`base:runtime`, `core:mem`) and no higher engine layer, keeping the engine package graph acyclic.

#### Scenario: Core memory builds without importing upward
- **WHEN** the engine is built with `-collection:engine=engine`
- **THEN** `engine:core` compiles without importing `platform`, `render`, or `game`, and the build is acyclic

