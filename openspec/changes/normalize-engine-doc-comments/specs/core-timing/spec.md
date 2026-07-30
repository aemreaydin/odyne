# core-timing Specification (delta)

## ADDED Requirements

### Requirement: The default fixed step divides evenly into nanoseconds
The default fixed timestep SHALL be a rate whose period is a whole number of nanoseconds,
so that the step carries no truncation residue. 50 Hz satisfies this at exactly 20,000,000 ns;
60 Hz does not, truncating to 16,666,666 ns — 0.67 ns short of a true 60 Hz step. 64 Hz
(15,625,000 ns) is the other exact option in this range.

This is a property of the constant itself, independent of the loop that consumes it. The
existing `game-loop` requirement "Zero-value configuration applies defaults" asserts that a
default step is exactly representable; this requirement is what makes that true and records
why the rate was chosen.

#### Scenario: The default step is exact
- **WHEN** the default fixed timestep is expressed in nanoseconds
- **THEN** it is a whole number, with no remainder discarded by integer division

#### Scenario: Derived simulated time is unaffected by rate choice
- **WHEN** simulated time is computed from a step count and the default step
- **THEN** the result is exact, because simulated time is a product rather than a sum of the step
