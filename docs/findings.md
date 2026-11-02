# Sample Footage Findings

Verification of the open questions in the spec ("先に検証すること"), using the sample
recording `DJI_20261102220407_0073_D.MP4` / `.LRF` (Osmo Action 6, recorded 2026-11-02
in the Philippines, `Asia/Manila`, UTC+8).

## Ground truth

The sample is a recording of a time-server web page that shows UTC with 1-second
resolution. The UTC row was OCR'd (tesseract, cropped to the row) on every frame near the
start and end of the clip. The frame at which the seconds digit flips pins the real UTC time
of that frame to within one frame (1001/24000 s ≈ 41.7 ms).

| Frame | PTS (s) | UTC shown flips to | Implied UTC of frame 0 |
| --- | --- | --- | --- |
| 8 | 0.3337 | 14:04:11 | 14:04:10.666 – .708 |
| 56 | 2.3357 | 14:04:13 | 14:04:10.664 – .706 |
| 703 | 29.3209 | 14:04:40 | 14:04:10.679 – .721 |
| 727 | 30.3220 | 14:04:41 | 14:04:10.678 – .720 |

Intersection: **frame 0 was captured at ≈ 14:04:10.69 UTC** (± ~20 ms, plus display/render
latency of the web page). Start and end agree, so the media timeline runs at real time
(no measurable drift over 30 s).

## Metadata (`exiftool -time:all -G1 -a -s`, `ffprobe`)

| Item | MP4 | LRF |
| --- | --- | --- |
| `creation_time` (movie, all tracks) | `2026-11-02T14:04:09Z` | same |
| Sub-second part | `.000000` (whole seconds only) | same |
| Duration | 30.739042 s | 30.739042 s |
| Video | HEVC `hvc1` 3840×2160, 10-bit `yuv420p10le`, 24000/1001 fps, 737 frames | H.264 1280×720, 8-bit, 24000/1001 fps, 737 frames |
| Other tracks | AAC, `djmd` (CAM meta), `dbgi` (CAM dbgi), `tmcd`, MJPEG thumbnail | AAC, `djmd`, `tmcd`, MJPEG thumbnail |
| Rotation matrix | identity | identity |
| Encoder tag | `DJI OsmoAction6` | same |
| `tmcd` timecode | `21:50:27:18` (unrelated to wall clock) | same |
| File name time | `20261102220407` (local, UTC+8) | same |
| File mtime on card | 22:04:42 +08:00 (≈ end of recording) | same |

## Answers to the spec's open questions

### Is `creation_time` the start or the end?

**Start.** `creation_time` (14:04:09) is before the first frame (14:04:10.69); the end of the
recording was ≈ 14:04:41.4. Using `creation_time − duration` would be off by ~30 s.

### UTC or local?

**UTC.** Local time at the shooting location (Philippines, UTC+8) was 22:04; `creation_time` is 14:04Z.
The file *name* is local time (22:04:07). So the time zone setting only matters for the
EXIF `OffsetTimeOriginal` and display, not for computing the absolute instant.

### Start offset (new finding)

`creation_time` is **≈ 1.69 s earlier** than the true capture time of frame 0
(the file name time is ≈ 3.69 s earlier). With Δ = 0 the spec's formula would miss the
±1 s acceptance criterion.

The 1.69 s mixes three things that a single sample cannot separate:

- `creation_time` is stored in whole seconds (truncation adds 0–1 s),
- a fixed pipeline delay between "record start" and the first encoded frame,
- the camera's clock error against UTC at the time of recording.

**Decision:** add a per-camera calibration constant `startLatency = 1.7 s`, applied before the
user's Δ:

```
T_capture = creation_time + startLatency + t + Δ
```

This keeps Δ = 0 as the user-facing default as the spec requires. Re-measure with a few more
clock recordings (ideally started at different sub-second phases) and update the constant
if the spread exceeds ±0.5 s.

### LRF vs. main file

- Same duration, frame rate and frame count (737) as the main file.
- The UTC seconds flip on the **same frame index** (8 and 703) in both files, so in this
  sample there is no frame offset between LRF and main file.
- LRF is 8-bit H.264 1280×720; main file is 10-bit HEVC 4K. Preview colors will differ from
  the export for 10-bit/D-Log footage, as the spec anticipated.

### Split files

Not verified — no long recording in the sample set yet.

## Implications for implementation

- `VideoMetadataReader` reads the movie-level creation date (`AVAsset.creationDate`) and
  treats it as UTC start.
- `CaptureTimeCalculator` gets a `startLatency` input (default 1.7 s for Osmo Action 6),
  separate from the user offset Δ.
- The LRF can be mapped to the main file 1:1 by time (ratio of durations = 1.0 here).
- The 10-bit HEVC source means frame extraction must handle 10-bit → HEIC conversion
  (open question "HDR / 10-bit color conversion" in the spec remains open).
