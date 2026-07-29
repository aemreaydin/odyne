# Interface design

> **Interface:** not applicable — concept lesson, no exercise interface.

## Learner sketch

Not applicable. This lesson has no code exercise; the deliverable is comprehension
(recall questions + probes) plus the machine census recorded in the journal.

## Tutor critique

Not applicable.

## Agreed interface

Not applicable.

The interface work this lesson prepares lands in the next two changes:

- **m20-02 (instance, device, queues, and the capability record)** — the learner designs how
  `engine/render` presents Vulkan initialization: what the device-selection policy is, what the
  created objects are called, and what (if anything) crosses the package boundary.
- **m20-03 (swapchain)** — presentation, image acquisition, and the resize path.

## Constraints carried into m20-02

Fixed by this lesson; m20-02's design conversation decides the *shape* of these, not whether
they hold.

1. **No `vk*` type in any signature outside `engine/render`** — the layering law from m01-01,
   restated for the renderer.
2. **A capability record exists, is built exactly once during device creation, and is
   thereafter immutable.** It holds resolved decisions (which core version, which optional
   extensions were actually obtained, which path each capability-dependent choice takes, which
   limits later code must respect) rather than raw query results. Nothing downstream re-queries
   the device.
3. **No `when ODIN_OS` in `engine/render`.** Platform variation enters through the capability
   record. Genuine OS-specific work — surface creation being the expected case — belongs behind
   the platform layer's existing seam.
4. **Modern path first, fallback second, both behind one capability check.** The modern route is
   the one designed and written first; fallbacks are added deliberately and identified as such.
5. **Fallback branches must be reachable in testing.** `VK_LAYER_KHRONOS_profiles` simulating a
   lower baseline is the intended mechanism — a fallback that has never executed is not a
   fallback.

Open for m20-02 to decide: whether the record is one flat struct or grouped by axis; whether
capability resolution is a separate procedure from device selection or a product of it; how a
hard-requirement failure is reported to `engine/game`; and which baseline odyne declares as its
floor.
