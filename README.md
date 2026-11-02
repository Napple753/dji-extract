# DJI Extract

Personal iOS app that cuts photos, Live Photos and short videos out of Osmo Action 6
recordings over USB-C and saves them to Photos with the capture time of the cut frame.

Spec (Japanese): `Osmo Action 6 切り出しアプリ 仕様書（USB接続版）.md`.
Sample footage verification: [docs/findings.md](docs/findings.md).

## Capture time

```
T_capture = creation_time + startLatency + t + Δ
```

- `creation_time` is the UTC start of the file (measured, see findings).
- `startLatency` = 1.7 s for Osmo Action 6 (measured from a clock recording).
- `t` is the position of the frame in the main file, `Δ` the per-video user offset (default 0).
- The time zone only affects EXIF offsets and display; it defaults to the iPhone's current zone
  and can be changed per video.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/DJIExtractCore` | Pure logic (Foundation only): `CaptureTimeCalculator`, timestamps, LRF time mapping, Live Photo range, DCIM file pairing |
| `Sources/DJIExtractKit` | Media: `VideoMetadataReader`, `FrameExporter`, `LivePhotoExporter`, `ClipExporter`, `PhotoLibrarySaver`, `CameraLibrary`, thumbnails, LRF preview |
| `Sources/DJIExtractUI` | SwiftUI screens (connect, list, editor, save, log) |
| `App/` | iOS app entry point |
| `project.yml` | XcodeGen spec for `DJIExtract.xcodeproj` |

## Tests (no Xcode needed)

```sh
scripts/test.sh            # Core + Kit tests; Kit tests use the sample footage at the repo root
scripts/typecheck-ui.sh    # type-checks the SwiftUI target with the Command Line Tools
```

The sample `DJI_20261102220407_0073_D.MP4` / `.LRF` are not committed. Kit tests that need
them are skipped when they are missing.

## Building for the iPhone (manual steps)

1. Install Xcode 26 and run `xcodegen generate` (after changing `project.yml`).
2. Open `DJIExtract.xcodeproj`, add your Apple ID in Xcode > Settings > Accounts, and choose the
   Personal Team under Signing & Capabilities.
3. Enable Developer Mode on the iPhone, build and run once from Xcode, and trust the developer
   in Settings > General > VPN & Device Management.
4. The free-account build expires after 7 days; run it again from Xcode to renew.
5. While the camera occupies the USB-C port, connect to Xcode over the network, or use the in-app
   Log screen.

The bundle ID is fixed to `xyz.napple.DJIExtract`.

## Status

Implemented: everything in the spec's first version, verified on macOS against the sample footage
(metadata, HEIC/EXIF, lossless and accurate clips, Live Photo files). Not yet verified on device:
USB folder access, playback, Photos saving, Live Photo playback in Photos, cable-pull handling.

Open items:

- Re-measure `startLatency` with more clock recordings (single sample so far).
- Split recordings (no sample yet).
- HDR / 10-bit to SDR conversion for stills (currently AVFoundation's `forceSDR`).
- Live Photo length (fixed at 3 s for now).
