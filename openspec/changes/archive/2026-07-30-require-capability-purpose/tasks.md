# Tasks: require-capability-purpose

## 1. Fix it at the source

- [x] 1.1 `.claude/skills/openspec-sync-specs/SKILL.md` step 4d instructs "Add Purpose section (can be brief, mark as TBD)" — that line is what manufactures the debt. Require a written Purpose instead
- [x] 1.2 Add a step to `.claude/skills/openspec-archive-change/SKILL.md` between the spec-sync assessment and the archive move: any capability spec still carrying a placeholder Purpose gets a written one. This is the backstop — the `openspec archive` CLI writes placeholders directly, without going through the sync skill
- [x] 1.3 Add the corresponding line to the archive skill's success output and to its Guardrails, so the step is visible in both the flow and the summary

## 2. Make it visible from the lesson side

- [x] 2.1 `openspec/schemas/lesson/templates/tasks.md`: extend the finalize hand-off task to name the Purpose obligation, so it reads as part of the ritual rather than as archive-skill trivia

## 3. Verify

- [x] 3.1 Confirmed against git history rather than memory — no live placeholder survives `3c0eecc`, and the delta specs never carried one, so `openspec/changes/archive/` had nothing to check. `git show 259ab99:openspec/specs/...` gave the real strings and turned up **two** variants, not one: `TBD - created by archiving change X.` and `TBD - created by syncing change X.` The `- created by ` prefix matches both, and the second variant is what exposed `/opsx:sync` as a second source
- [x] 3.2 `openspec validate --all` passes
- [x] 3.3 Commit and push
