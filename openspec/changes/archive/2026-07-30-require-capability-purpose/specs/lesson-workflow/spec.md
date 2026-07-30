# lesson-workflow Specification (delta)

## MODIFIED Requirements

### Requirement: Archive ritual
Archiving a lesson SHALL produce all of the following, via the lesson's finalize task group plus the standard archive command: (1) spec deltas merged into `openspec/specs/`; (2) the lesson explanation — measured numbers included — persisted under `curriculum/modules/<module>/<lesson>/`; (3) `curriculum.yaml` updated (lesson `done`, newly unblocked lessons `available`); (4) a written Purpose on every capability spec the archive created, describing what the capability covers and where its boundary sits.

A capability spec SHALL NOT be left carrying the placeholder Purpose the archive command writes when it creates the file. Because that placeholder does not exist until the archive runs, effect (4) SHALL be discharged by the archive step itself rather than by a finalize task.

#### Scenario: Lesson completes
- **WHEN** review is complete and the lesson change is archived
- **THEN** all four effects are present in the repository in the same commit or commit series

#### Scenario: A lesson introduces a new capability
- **WHEN** the archive creates `openspec/specs/<capability>/spec.md` for a capability that did not exist before
- **THEN** that spec's Purpose describes the capability, and no placeholder text remains in it

#### Scenario: A lesson only extends existing capabilities
- **WHEN** the archive merges deltas into capability specs that already exist
- **THEN** their existing Purposes are left alone and no new Purpose is required
