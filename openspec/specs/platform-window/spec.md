# platform-window Specification

## Purpose
TBD - created by archiving change lesson-m10-01-win32-window. Update Purpose after archive.
## Requirements

### Requirement: Native window lifecycle
The engine platform layer SHALL create and destroy native operating-system windows addressed by distinct opaque handles, with configurable title and client size and zero-value defaults. Every operation taking a window handle SHALL reject invalid handles — zero, stale, or foreign — by returning an error or a zero value, never by crashing.

#### Scenario: Create yields an open window
- **WHEN** a window is created with a requested client size
- **THEN** a valid handle is returned, the window reports open, and its client size matches the request

#### Scenario: Zero-value configuration applies defaults
- **WHEN** a window is created from a zero-value description
- **THEN** a visible window with the default title and default client size is produced

#### Scenario: Destroy closes the window and stales the handle
- **WHEN** an open window is destroyed via its handle
- **THEN** the native window is closed, the handle no longer reports open, and a second destroy with the same handle returns an error

### Requirement: Close is a request, not a command
A user close action (close button, Alt+F4) SHALL be recorded as a close request observable through the platform API; the window SHALL remain open and functional until the application explicitly destroys it.

#### Scenario: Close request observed, window still open
- **WHEN** the user requests close and events are next polled
- **THEN** the window reports close-requested while still reporting open, and a subsequent explicit destroy succeeds

### Requirement: Non-blocking event pump
The platform layer SHALL provide a per-frame event pump that drains all pending OS messages for the calling thread's windows and returns without blocking, whether or not messages are pending. Window state observable through the API (size, close-requested) SHALL reflect all messages processed by the pump.

#### Scenario: Idle pump returns immediately
- **WHEN** the pump is called with no pending messages
- **THEN** it returns without blocking

#### Scenario: Resize is reflected after the pump
- **WHEN** the native window is resized and events are polled
- **THEN** the reported client size matches the new size

### Requirement: OS-type confinement
No operating-system-specific type (native window handles, message structures, OS binding types) SHALL appear in any public platform signature, and OS binding packages SHALL be imported only within the platform layer. Multiple windows SHALL be independently addressable through their handles, and destroying one window SHALL NOT disturb the state or event routing of another.

#### Scenario: Upper layers compile against platform types only
- **WHEN** an application uses the platform window API
- **THEN** it compiles referencing only platform-defined types, with no OS binding import

#### Scenario: Destroying one window leaves another intact
- **WHEN** two windows exist and one is destroyed
- **THEN** the surviving window still reports open, and its subsequent events (e.g. a close request) are routed to it correctly

### Requirement: Uniform error reporting
Window queries SHALL answer benign zero values for invalid handles. Window mutators and system initialization SHALL report failure through the platform error type: a mutation through an invalid handle SHALL return an invalid-handle error with no side effects, and a failed initialization SHALL return an initialization error while leaving any already-initialized window system undisturbed. Purely cosmetic native failures (e.g. a title change the OS rejects on a live window) MAY be best-effort. (Supersedes the silent no-op mutator grammar from lesson-m10-02 amendment 4.)

#### Scenario: Mutation through an invalid handle reports an error
- **WHEN** a mutator (close request, title change) is called with a zero or stale handle
- **THEN** it returns an invalid-handle error and no window state changes

#### Scenario: Failed re-initialization leaves the system intact
- **WHEN** the window system is initialized a second time without an intervening shutdown
- **THEN** the call reports an initialization error and previously created windows remain open and functional

### Requirement: Headless-capable windows
Window creation SHALL support a hidden mode producing a fully functional window — real native handle, message processing, size queries — that never appears on screen, so automated tests can exercise the full lifecycle headlessly.

#### Scenario: Hidden window lifecycle runs under the test runner
- **WHEN** a hidden window is created, pumped, close-requested, and destroyed inside a unit test
- **THEN** all lifecycle behavior matches a visible window's and nothing is shown on screen
