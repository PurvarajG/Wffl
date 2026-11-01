# Final release native interaction checks

26 October 2026. Tested the isolated `/tmp/wffl-final-opening/Wffl Final Opening.app` after the final active/pending surface fix and background-bake guard. No installed app or live library was used.

- Actual wheel input moved the tour from 0% to 21%, then backward to 13%.
- From Your Mac, wheel input opened the cubes to 34%; reverse input moved them back to 21%.
- Resized the open reveal from 1100×700 to 900×560 using the review menu. The visible scene retained its partially opened cubes, and refreshed content resumed at the current progress.
- Reversed fully back into the tour (44% overall), then checked keyboard progression and the review cube jump.
- Escape removed the overlay and returned to native Ask.
- Focused the native search field, replayed the opening, clicked Skip, and typed `release focus check` without refocusing the field. Accessibility confirmed the search field held that value. The test text was cleared.
- Replayed to Your Mac and completed the reveal by scrolling. Accessibility confirmed that the welcome modal disappeared, the Ask sidebar/search became available, and the search field received focus.
- Relaunched compact/light with the review-only Reduced Motion override. Back returned to the initial still; nine forward steps reached the manual feature tour, four more reached Your Mac with Done. Done completed directly into Ask. The system accessibility preference was not changed.
- The current welcome/film test log contains 34 passing tests, including automatic-to-manual boundary, repeated folding seeks, reversal, replay, interruption and acknowledgement policy. The final changed Swift sources precede that test log.
- Four native keyframe runs cover dark/light at 1100×700 and 900×560, 28 keyframes each. Source-to-rest interior pixel comparisons exceed 99.999% within two RGB levels. See `verification-final-release-v1-keyframes.json` for the exact values.

The review preview uses inert readiness fixtures, so its model-download and microphone readiness notices represent those fixtures. Production still uses the application's current state. Native window exports require an unlocked Mac.
