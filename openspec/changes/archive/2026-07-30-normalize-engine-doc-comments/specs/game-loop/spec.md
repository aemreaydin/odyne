# game-loop Specification (delta)

## ADDED Requirements

### Requirement: The engine-owned loop is a convenience, not the only path
The timing components the loop is built from — the frame clock, the pacer, the frame-time
history, and the deadline waiter — SHALL remain fully usable without the engine-owned loop,
depending on nothing in the `game` layer. A tool, an asset cooker, or a test harness SHALL be
able to write its own iteration over them.

The engine-owned loop exists because inverting control is the only shape available on
platforms where an application-owned infinite loop is not permitted to exist, and it is the
shape the platform layer's own backend offers [SDL SDL_AppIterate], [SOKOL]. It is not a
constraint on callers who can own their loop.

#### Scenario: Timing components driven without the loop
- **WHEN** a caller drives the frame clock and pacer directly, never entering the engine-owned loop
- **THEN** both function fully, and neither requires any facility from the `game` layer

#### Scenario: Loop placement keeps dependencies downward
- **WHEN** the frame loop's imports are inspected
- **THEN** every dependency points downward along `core → platform → render → game`, with no upward call into application code routed through a lower layer
