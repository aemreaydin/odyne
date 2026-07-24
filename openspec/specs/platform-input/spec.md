# platform-input Specification

## Purpose
TBD - created by syncing change lesson-m10-02-input. Update Purpose after archive.
## Requirements

### Requirement: Portable input currency
The engine platform layer SHALL expose keyboard and mouse input through platform-defined key and button identities; no operating-system key code, message constant, or binding type SHALL appear in any public input signature. Native keys with no platform mapping SHALL be ignored safely. Left and right variants of modifier keys SHALL be distinguishable. Every input query taking a window handle SHALL answer with a zero value for invalid handles — zero, stale, or foreign — never by crashing.

#### Scenario: Unmapped native key is ignored
- **WHEN** a native key message carrying an unmapped key code is processed
- **THEN** no platform key changes state and nothing crashes

#### Scenario: Left and right modifiers distinguished
- **WHEN** the native messages for the left and right variants of a modifier key are processed
- **THEN** each variant is observable as its own platform key, independently

#### Scenario: Invalid handle yields zero values
- **WHEN** input queries are called with a zero or stale window handle
- **THEN** they return false, zero position, and zero wheel — never crash

### Requirement: Frame-coherent snapshot with transition capture
Input queries SHALL answer from per-window state fixed at the most recent event pump: messages arriving after a pump SHALL NOT be observable until the next pump, and all queries between two pumps SHALL agree. Press and release edges SHALL derive from transitions captured at message-processing time, such that a press and release completing entirely within one pump interval is still observable as both a press edge and a release edge in that frame.

#### Scenario: State is fixed at the pump
- **WHEN** a key-down message is posted but events are not yet pumped
- **THEN** the key does not report down; after the pump, it does

#### Scenario: Press edge lasts exactly one frame
- **WHEN** a key goes down and events are pumped, then events are pumped again with no further messages
- **THEN** the key reports a press edge in the first frame only, while reporting down in both

#### Scenario: Release edge observed
- **WHEN** a held key's key-up message is pumped
- **THEN** the key reports a release edge that frame and no longer reports down, and the edge is gone the following frame

#### Scenario: Sub-frame tap is not lost
- **WHEN** a key's down and up messages both arrive within a single pump interval
- **THEN** that frame reports both a press edge and a release edge while the key does not report down

### Requirement: Key repeat produces no edges
Automatic key-repeat messages for a key already held down SHALL NOT produce press edges or transitions; the key SHALL simply continue to report down.

#### Scenario: Repeat while held
- **WHEN** a held key's autorepeat key-down message is pumped
- **THEN** the key reports down but no press edge

### Requirement: Mouse state — position, buttons, wheel
The platform layer SHALL report the mouse position in signed client-relative pixels (negative coordinates preserved), mouse buttons with the same level-and-edge semantics as keys, and wheel motion as a signed fractional detent count (one detent = one standard wheel notch, positive away from the user) accumulated across each frame and reset at the pump.

#### Scenario: Motion updates position
- **WHEN** a mouse-move message is pumped
- **THEN** the reported position matches the message's client coordinates

#### Scenario: Negative coordinates preserved
- **WHEN** a mouse-move message carries negative client coordinates
- **THEN** the reported position is negative, not a large positive artifact

#### Scenario: Button edges
- **WHEN** a button-down message is pumped, then a button-up message is pumped in a later frame
- **THEN** the first frame reports the button down with a press edge, and the later frame reports a release edge with the button up

#### Scenario: Wheel accumulates within a frame and resets after
- **WHEN** two wheel messages totaling one and a half detents are pumped in one frame
- **THEN** that frame reports 1.5 detents and the next frame reports zero

### Requirement: Mouse capture across drags
The platform layer SHALL capture the mouse on the first button-down and release the capture on the last button-up, so that drags leaving the client area still deliver their motion and release messages to the originating window. If the system reassigns capture elsewhere mid-chord, the platform SHALL treat the chord as ended — clearing that window's button state silently — and SHALL NOT re-acquire capture or release the new owner's capture.

#### Scenario: Capture follows the button chord
- **WHEN** buttons go down and up in an overlapping sequence
- **THEN** the thread's capture window is the originating window from the first down until the last up, and no window holds capture afterward

#### Scenario: Stolen capture ends the chord
- **WHEN** another window takes capture mid-chord and the stale button-up arrives later
- **THEN** the original window's buttons clear without release edges and the new owner's capture is left intact

### Requirement: Focus is observable
The platform layer SHALL expose whether a window currently holds keyboard focus, as a frame-coherent query updated by the native focus-gain and focus-loss messages. Invalid handles SHALL report unfocused.

#### Scenario: Focus tracks gain and loss
- **WHEN** focus-gain and focus-loss messages are pumped
- **THEN** the window reports focused after the gain and unfocused after the loss, while an invalid handle always reports unfocused

### Requirement: Focus loss clears input silently
When a window loses native input focus, all of its key and button levels, pending transitions, and pending wheel accumulation SHALL be cleared without producing press or release edges. The last-known mouse position SHALL persist. If the window holds mouse capture when focus is lost, the capture SHALL be released.

#### Scenario: Held key vanishes without an edge
- **WHEN** a key is held and the window's focus-loss message is pumped
- **THEN** the key no longer reports down and no release edge is reported

#### Scenario: Cursor position persists
- **WHEN** the mouse has moved and the window's focus-loss message is then pumped
- **THEN** the reported position remains the last-known coordinates, not zero

#### Scenario: Focus loss mid-chord releases capture
- **WHEN** a button is held with capture taken and the window's focus-loss message is pumped
- **THEN** no window holds capture afterward, and the button clears without a release edge

### Requirement: Per-window input routing
Input state SHALL be tracked per window: messages routed to one window SHALL NOT alter another window's observable input state.

#### Scenario: Two windows, independent state
- **WHEN** a key-down message is posted to one of two open windows and events are pumped
- **THEN** only that window reports the key down

### Requirement: System keys observed, never consumed
System-key messages (Alt-modified keys, F10) SHALL update platform input state AND be forwarded to default OS processing, so system commands (Alt+F4, Alt+Tab, menu activation) keep working.

#### Scenario: Alt observable as a key
- **WHEN** a system-key-down message for the Alt key is pumped
- **THEN** the Alt key reports down through the platform API (default forwarding verified at the demo checkpoint: Alt+F4 still produces a close request)
