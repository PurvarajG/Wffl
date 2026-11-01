# Focused release integration review

**Source verdict: no remaining actionable material findings.** Final focused source inspection includes the active/pending resize swap and the `pendingFoldSurface == nil` refresh guard.

Reviewed against `docs/superpowers/plans/2026-10-26-final-release-stitch.md`, the saved production baseline, and approved v8 handoff source. Scope: production FoldSurfaceView, WelcomeFoldHost, OpeningTourCapture, WelcomeJourneyView/shared chrome, opening controller, native overlay/focus lifecycle, and FinalOpeningApp exporter. No broad audit, UI automation, native capture, or duplicate builds/tests were run by this reviewer.

The review found and resolved two material lifecycle issues before verdict: resize formerly restored a flat page while baking, and the initial pending bake could be repeatedly canceled by continued input. The final implementation retains the active baked scene while a hidden replacement bakes, swaps at the latest progress, and suppresses no-surface refresh while that pending surface exists. New resize work cancels pending capture/bake; reversing to zero or dismantling releases both surfaces. Readiness tracks installed active content, and repeated folding seeks retain valid readiness.

Approved equal-cube geometry/physics values, native source pixels including chrome, automatic-to-manual boundary, reversible input, fixed underlying Ask, Skip/Escape/completion/acknowledgement, replay, Reduced Motion, focus restoration, and cancellation were checked within this scope without additional material findings.

Evidence read: `/tmp/wffl-release-stitch-report.md` and `/tmp/wffl-final-release-tests.log` (34 selected tests, zero failures). That test log precedes the final one-condition pending-surface guard. The final preview rebuild and serial native interaction/movie verification remain owned by the lead. Lead reports the four 28-frame appearance/size matrices passed source-fidelity checks and visual inspection; this reviewer did not independently reproduce those captures.
