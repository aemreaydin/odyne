# core-timing Specification (delta)

## ADDED Requirements

### Requirement: Clock and pacer are separately responsible
Measuring real time and deciding how much simulation it buys SHALL be separate
responsibilities. The frame clock SHALL be the only component that reads a platform clock;
the pacer SHALL read no clock, make no syscall, and allocate nothing, operating purely as
integer arithmetic over durations handed to it [GAFFER-TIMESTEP].

This separation is what makes pacing testable with fabricated deltas, and it is why the
pacer carries no platform dependency.

#### Scenario: Pacer exercised without a platform clock
- **WHEN** the pacer is driven entirely by fabricated frame deltas in a test
- **THEN** it produces the same step counts and interpolation phase as it would in a running frame loop, with no platform clock involved

#### Scenario: Pacer performs no I/O
- **WHEN** the pacer advances a frame
- **THEN** it makes no syscall and performs no allocation

### Requirement: The fixed step is chosen to divide evenly into nanoseconds
The default fixed timestep SHALL be a rate whose period is a whole number of nanoseconds,
so the step carries no truncation residue. 50 Hz (20,000,000 ns) satisfies this; 60 Hz does
not, truncating to 16,666,666 ns.

#### Scenario: Default step is exact
- **WHEN** the default fixed timestep is expressed in nanoseconds
- **THEN** it is an exact whole number, with no remainder discarded by integer division
