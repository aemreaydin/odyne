# Review rubric

Run after the learner reports tests green. Verify green yourself (`odin test`) before reviewing.

## Checklist

1. **Correctness beyond the tests** — edge cases the tests don't cover: zero-size requests,
   alignment, overflow paths, empty/full boundaries, error returns. Name them; don't fix them.
2. **Idiomatic Odin** — naming conventions, `defer` usage, ZII friendliness, multiple return
   values vs out-params, `context` usage, parapoly where it helps. Flag C++-isms (getter/setter
   reflexes, unnecessary encapsulation, RAII reflexes) as "C++ habit" notes with the Odin way.
3. **Memory behavior** — who allocates, who frees, which allocator, lifetime story. Leak check
   clean. Hidden allocations (implicit `context.allocator` use) called out.
4. **Performance** — allocation count per op, cache behavior of the data layout, obvious
   wins left on the table. Tie observations to the lesson's Performance notes and the
   measurement task's numbers.
5. **Layering law** — imports point only downward along `core → platform → render → game`.
   Any upward import is a violation: name it, require the fix before archive.
6. **Handle-based boundaries** — cross-package APIs expose handles/values, not internal
   pointers or backend types (no `vk*` outside the Vulkan package, ever).
7. **Comprehension probes** — ask **at least two** questions targeting the lesson's core
   concept (why this design, what breaks if X, what's the cost of Y). Wait for answers;
   probe follow-ups if the answers are shaky. The lesson is not done until answered.
8. **Tutor self-check** — answer honestly in the review output: *"Did the tutor write any
   implementation code this lesson?"* If yes, say so plainly and note what the learner
   should redo to get the learning value back.

## Output shape

Findings ordered by severity (boundary violations and correctness first), each with
file:line, why it matters, and — for teaching value — a question before a prescription.
Close with the probes, then the verdict: ready to finalize, or what must change first.
