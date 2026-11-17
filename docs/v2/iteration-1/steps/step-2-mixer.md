# Step 2: stop the mixer inserting silence

**Rules served:** 3 (every second accounted for). It also makes timestamps match real time.
**Checked in advance:** yes.
**Owner approval needed:** no.

## What is wrong today

`MixBus` wakes every 200 ms and combines whatever the microphone and system audio have
delivered. The two arrive in bursts of different sizes. Each tick takes the longer of the two
amounts, pads the shorter one with zeros, and empties both queues.

So about twice a second, a short stretch of silence is spliced into whichever track delivered
less. On the 2026-11-15 recording that put 2,509 gaps, 173 seconds in total, into the
microphone track. The recording is 1,367 seconds long for about 1,196 seconds of real time,
and every timestamp after the first minute is wrong.

## What this step changes

When both sources are live, a tick emits only as many samples as **both** have delivered, and
leaves the rest in its queue for the next tick. Nothing is padded.

Padding now happens in three cases only:

- one source has run more than one second ahead of the other, which means the slow one has
  stalled (`maxLeadSamples`);
- the microphone is muted, so it is delivering nothing on purpose;
- the final flush when recording stops.

`tick` changes from `private` to internal, with a `flush` parameter, so the tests can drive it.

## Before you start

- [ ] Step 1 is committed.
- [ ] `swift test` passes.

## Do it

### With the patch (preferred)

```bash
git apply --check docs/v2/iteration-1/reference/step-2.patch
```

```bash
git apply docs/v2/iteration-1/reference/step-2.patch
```

### By hand

1. **Replace** `Sources/Wffl/Audio/MixBus.swift` with
   `docs/v2/iteration-1/reference/MixBus.swift`.
2. **Copy** `docs/v2/iteration-1/reference/MixBusClockTests.swift` to `Tests/WfflTests/`.

No other file changes. Every caller uses `pushMic`, `pushSystem`, `start`, `stop` and the three
callbacks, and those are unchanged.

## The new tick, in words

```
n = the longer of the two queues
if this is not the final flush, and system audio is on, and the mic is not muted:
    n = the shorter of the two queues
    if the longer is more than 48,000 samples (1 s) ahead: n = the longer   # stop waiting
if n is 0: return
take up to n samples from each queue, leaving the rest queued
measure each track's level
pad either track with zeros up to n          # only reached in the three cases above
mix, limit, and call the three callbacks
```

## Verify

```bash
swift test --filter MixBusClockTests 2>&1 | grep "Test Case" | grep -E "passed|failed"
```

Expect: three test cases, all `passed`.

- `testMixerAddsNoGapsWhenSourcesArriveInDifferentBursts` sends ten seconds of audio in which
  every sample is 1.0, in 4,096-sample and 960-sample bursts. It asserts the output is exactly
  as long as the input and contains no zero.
- `testMixerStopsWaitingForASourceThatStalls` sends microphone audio only, with system audio
  switched on but silent, and asserts all ten seconds are still recorded.
- `testMicOnlyRecordingPassesStraightThrough` covers system audio switched off.

```bash
swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3
```

Expect: `Executed 332 tests, with 3 tests skipped and 0 failures`.

The existing mute tests in `MeetingJul27RegressionTests.swift` must still pass. They did in
the advance check.

## Done when

- [ ] All tests pass, including the three new ones and the existing mute tests.
- [ ] STATUS.md is updated.

## Do not

- Do not change the 200 ms timer.
- Do not change what happens when the microphone is muted: its samples are still dropped
  before they reach the queue, by design.
- Do not try to repair old recordings. The gaps already in them are permanent.

## Commit

```
fix(audio): mixer no longer pads the shorter input with silence

Each 200 ms tick took the longer of the mic and system queues and zero-padded
the other, splicing about 80 ms of silence into speech twice a second and
making recordings 14% longer than real time. A tick now emits what both
sources have delivered and carries the remainder over. Padding happens only
when a source has stalled for a second, the mic is muted, or on the final flush.
```
