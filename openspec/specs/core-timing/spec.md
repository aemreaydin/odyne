# core-timing Specification

## Purpose
Real-time measurement and fixed-step pacing for the frame loop: a monotonic frame clock,
a fixed-capacity frame-time history, a deadline waiter, and the fixed-timestep pacer that turns
elapsed real time into whole simulation steps. Lives in the `core` layer and depends on no
platform facility, so it is usable without a window.

## Requirements

### Requirement: Monotonic frame timing

The engine SHALL provide a frame clock whose timeline is monotonic and whose total elapsed time is derived by subtracting a stored origin from the current timestamp, never accumulated from per-frame deltas. The clock SHALL accept the timestamp as a caller-supplied parameter so that the entire state machine is drivable without reading a real clock. Absolute time SHALL be held as integer nanoseconds; floating-point representations SHALL appear only at query boundaries.

#### Scenario: Elapsed is exact over a long session

- **WHEN** a clock is initialized at an arbitrary non-zero origin and advanced through 100,000 frames of varying deltas
- **THEN** the reported elapsed time equals the final timestamp minus the origin exactly, with no accumulated error

#### Scenario: The frame counter and delta follow the supplied timestamps

- **WHEN** the frame is advanced with a fabricated timestamp
- **THEN** the reported delta is that timestamp minus the previous one, the frame index increases by one, and no real clock is consulted

#### Scenario: A zero-length frame is legal

- **WHEN** the frame is advanced with the same timestamp twice
- **THEN** the reported delta is zero and the clock remains in a valid state

### Requirement: Spike clamping preserves the measured truth

The frame clock SHALL apply a configurable clamp policy — a threshold and a substituted delta — to the delta it reports for simulation, while keeping the unclamped measurement observable. Clamping SHALL be disableable. Once a frame has been clamped, the sum of reported deltas SHALL NOT be expected to equal elapsed time; elapsed time SHALL remain the real, unclamped quantity.

#### Scenario: A hitch is clamped and still observable

- **WHEN** a frame's measured delta exceeds the configured threshold
- **THEN** the delta reported for simulation is the configured substitute, the unclamped delta remains readable, and elapsed time reflects the real duration

#### Scenario: Normal jitter passes through untouched

- **WHEN** a frame's measured delta is below the threshold
- **THEN** the reported delta equals the measured delta

### Requirement: Fixed-capacity frame-time history

The engine SHALL record recent real frame durations in a fixed-capacity window that allocates no memory at any point, and SHALL report the window's mean, minimum, and maximum. Statistics SHALL be computed over the samples actually present, both before and after the window has filled, and SHALL answer a benign zero when it is empty.

#### Scenario: Statistics over a partially filled window

- **WHEN** fewer samples than the capacity have been recorded
- **THEN** the mean, minimum, and maximum describe only the recorded samples

#### Scenario: The window evicts its oldest sample

- **WHEN** more samples than the capacity have been recorded
- **THEN** the statistics describe exactly the most recent capacity-many samples, including after the previous extreme has been evicted

#### Scenario: An empty window is safe to query

- **WHEN** statistics are read before any sample has been recorded
- **THEN** zero is reported and no division by zero occurs

### Requirement: Deadline waiting never returns early

The engine SHALL provide a wait that blocks until a caller-supplied deadline and returns the timestamp it actually reached, so that the caller needs no additional clock read. The wait SHALL NOT return before the deadline, SHALL return immediately when the deadline has already passed, and SHALL yield time to the operating system for the bulk of the interval rather than busy-waiting the whole of it.

#### Scenario: The deadline is never undershot

- **WHEN** the wait is asked for a deadline in the future
- **THEN** it returns at or after that deadline, and the returned timestamp is at or after it

#### Scenario: A past deadline returns at once

- **WHEN** the wait is asked for a deadline that has already passed
- **THEN** it returns immediately without sleeping

### Requirement: Fixed-timestep pacing

The engine SHALL provide a pacer that converts elapsed real time into a whole number of fixed-size simulation steps, and SHALL report both that count and the leftover phase. Advancing the pacer SHALL consume real time only in whole steps; the count MAY be zero and zero SHALL be a legal, expected outcome. The pacer SHALL perform no allocation, consult no clock, and depend on no platform facility.

#### Scenario: A frame shorter than one step takes no steps

- **WHEN** the pacer is advanced by less time than one fixed step
- **THEN** the reported count is zero, simulated time is unchanged, and the deposited time is retained

#### Scenario: A long frame takes several steps

- **WHEN** the pacer is advanced by five times the fixed step
- **THEN** the reported count is five and simulated time advances by exactly five steps

#### Scenario: An exact multiple leaves no remainder

- **WHEN** the pacer is advanced by exactly one fixed step from an empty accumulator
- **THEN** the reported count is one and the reported phase is zero

### Requirement: Time fed to the pacer is conserved

For any sequence of deltas fed to the pacer, the total SHALL equal the simulated time consumed plus the unspent remainder, exactly, for the lifetime of the pacer. Simulated time SHALL be derived from the number of steps taken multiplied by the fixed step, never accumulated by repeated addition.

#### Scenario: Conservation holds over a long jittered session

- **WHEN** 100,000 frames of varying deltas are fed to the pacer
- **THEN** the sum of the deltas equals simulated time plus the remaining accumulator, with zero error

#### Scenario: Simulated time is a product, not a sum

- **WHEN** simulated time is read after any number of steps
- **THEN** it equals the step count multiplied by the fixed step exactly, regardless of the delta pattern that produced it

### Requirement: Interpolation phase is always publishable

The pacer SHALL report a phase between the last completed step and the next, as a value in the half-open range from zero to one, after every advance including advances that took no steps. The value one SHALL be unreachable, because a full step's worth of accumulated time is always consumed as a step.

#### Scenario: The phase stays in range under arbitrary deltas

- **WHEN** the pacer is advanced repeatedly by arbitrary non-negative deltas
- **THEN** the reported phase is at least zero and strictly less than one after every advance

#### Scenario: A zero delta advances nothing and changes no phase

- **WHEN** the pacer is advanced by a zero delta
- **THEN** the count is zero, and the phase and simulated time are unchanged from before the advance
