Fixes from the first long real meeting recorded on 2.1.

- **Long meetings stay cool.** The window no longer redraws every time the audio level changes, which kept one processor core busy and made the Mac hot after about 40 minutes.
- **Lighter live draft.** While recording, the draft uses Parakeet only. The full transcript after Stop & Save still uses BAPS Whisper, so its accuracy does not change.
- **Start errors are visible.** If a recording cannot start, Wffl now says why and does not leave an empty meeting behind.
- **Recordings survive a crash.** If Wffl closes during a recording, the audio is repaired and linked to its meeting the next time Wffl opens. Click Retranscribe to finish it.

**Full Changelog**: https://github.com/PurvarajG/Wffl/compare/v2.1.0...v2.1.1
