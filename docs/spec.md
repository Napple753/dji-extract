# Osmo Action 6 Extract App Spec (USB Version)

Nov 2, 2026 · @ICHIKAWA Ren

## Purpose and scope

A personal app that cuts stills and clips out of Osmo Action 6 videos over USB-C and saves them
to Photos with the capture time of the cut moment. The first version runs with a free Apple ID.

| Item | Details |
| --- | --- |
| Camera | Osmo Action 6 |
| Device | iPhone 17 (USB 2, up to 480 Mbps) |
| OS | iOS 26 or later |
| Connection | USB-C cable only |
| Distribution | Direct install to my own iPhone |
| External libraries | None. Built with SwiftUI, AVFoundation, ImageIO and PhotoKit |

**In scope for the first version**

- List the videos on the camera and preview them with the LRF
- Cut out a photo, a Live Photo or a short video
- Save to Photos with the calculated capture time

**Out of scope for the first version**

- Wi-Fi and Bluetooth connections
- Modifying or deleting files on the camera
- Color correction or grading of D-Log footage
- Live wallpapers, slow motion and timelapse
- Cuts spanning split files
- Fixing dates of photos and videos already exported from Mimo

## To verify first

The USB connection is confirmed. The rest is checked at the start of implementation with real
files placed in the project folder.

| Item | Status / method | What the result changes |
| --- | --- | --- |
| Recognized by the iPhone Files app | Confirmed. Both internal storage and SD can be browsed | Proceed with the USB version |
| Is `creation_time` the start or the end? | Check with the sample MP4 and LRF | Reference time of the formula |
| Is `creation_time` UTC or local? | Compare the sample's value with the time of recording | Time zone handling |
| Split information | Compare if a long recording sample is available | Handling of split files |

Check the metadata with [ExifTool](https://exiftool.org/forum/index.php?msg=65547):
`exiftool -time:all -G1 -a -s`. QuickTime dates are UTC by specification, but many cameras
record local time, so this has to be measured.

**Additional LRF check**

Compare the duration and fps of the sample LRF and the main file.

## Screens and flow

There are four screens, moving in one direction from connection to saving.

1. **Connect:** Choose the DCIM folder on internal storage or SD. Skipped when the previous
   folder can be read.
2. **List:** Videos newest first, with thumbnail, capture start time and duration.
3. **Cut:** Find the position with playback and frame stepping. The capture time at that position
   is always shown.
4. **Save:** Confirm the format and time, save, and show the result.

Operations on the cut screen:

| Operation | Details |
| --- | --- |
| Seek | Move roughly with a slider |
| Frame step | Move one frame back or forward |
| Photo | Save the current frame |
| Live Photo | Save about 3 s centered on the current frame |
| Video | Save between a chosen start and end point |
| Time correction | Change the offset in seconds and the time zone |

The time correction is kept per video and reused for the next cut from the same video.

## File access

The camera is chosen with a folder picker and treated as read-only.
[The iOS document picker returns security-scoped URLs](https://developer.apple.com/forums/thread/691922),
so no special entitlements are used.

- **Selection:** Pick a `.folder` with SwiftUI's `fileImporter`.
- **Access:** Pair `startAccessingSecurityScopedResource` and `stop…` around each read.
- **Reconnection:** Save a bookmark and resolve it next time. If it cannot be resolved, return
  to the connect screen.
- **Target files:** `.MP4` and `.MOV` under DCIM. Filter by extension; unreadable files are shown
  as disabled in the list.
- **Low-resolution files:** If an LRF with the same name exists, pair it with the main file and use
  it for the list and preview.
- **Writing:** Never to the camera.
- **Temporary files:** Exports happen in the app's temporary area and are deleted after saving
  to Photos.

**Transfer speed assumptions**

[The iPhone 17's USB-C is limited to 480 Mbps](https://www.slashgear.com/1981170/how-fast-is-the-usb-port-iphone-17/),
much slower than the Pro models' 10 Gbps. Assuming about 40 MB/s in practice, copying 16 GB takes
about 7 minutes.

- Do not copy the main file; preview with the LRF.
- When exporting, read only the range being cut.
- Cache thumbnails in the app after generating them, so they are not re-read on reconnection.
- For videos without an LRF the main file is played directly; check on device whether playback
  and seeking are practical.

**Separating preview and export**

Preview uses the LRF, export uses the main file. The LRF is
[a low-resolution file created alongside the recording](https://forum.dji.com/thread-233111-1-1.html),
also used by Mimo's trimmed download.

1. When a video is opened, open the LRF with the same name as an `.mp4` directly on the camera
   (no copy: on long recordings, copying the LRF alone delays the start of playback a lot).
2. Playback, seeking and frame stepping use the LRF. Its low bitrate is enough over USB.
3. The cut position is kept in seconds. If the LRF and main file durations differ, convert
   proportionally.
4. Before saving, fetch the corresponding frame of the main file and show it on the confirmation
   screen.
5. Photo, Live Photo and video export and the time calculation use only the main file.

Step 4 is needed because the LRF and main file
[may be off by about one frame](https://forum.dji.com/thread-233111-1-1.html). The LRF is
[said to be 8-bit Rec.709](https://4ddig.tenorshare.com/tw/video-recovery/what-is-lrf-file.html),
so with D-Log footage its colors also differ from the main file. Stepping on the confirmation
screen reads the main file to settle the final frame.

If there is no LRF, it cannot be read, or the durations differ by more than 1 s, play the main file
directly.

## Capture time calculation

The capture time of the cut position is the file's start time plus the time elapsed from the start
of the video.

```latex
T_{capture} = T_{start} + t + \Delta
```

| Symbol | Meaning |
| --- | --- |
| T\_start | Capture start time of the file |
| t | Seconds from the start of the video to the cut position |
| Δ | User correction in seconds. Defaults to 0 |

**Finding T\_start**

- If `creation_time` is the start time, use it.
- If it is the end time, use `creation_time − duration`.
- The value is likely whole seconds, giving an error of about ±1 s.

**Time zone**

- If `creation_time` is UTC, use it as an absolute time.
- If it is local time, apply the capture location's time zone to get an absolute time.
- The capture location defaults to the device's current time zone and can be changed per video.
- Processing travel footage after returning home gives the wrong default, so confirming the time
  before saving is mandatory.

**Split files**

Long DJI recordings are split into several files. Earlier models
[split at around 4 GB or 16 GB](https://forum.dji.com/thread-304742-1-1.html). The calculation uses
each file's `creation_time`. If split files turn out to have unreliable values, derive the start
from the previous file's start time and duration.

## Output

The same capture time is written both to the Photos creation date and to the metadata inside the
file, so the time survives exporting.

| Format | Contents | Reference moment | Time written to |
| --- | --- | --- | --- |
| Photo | HEIC of the current frame | Current frame | EXIF `DateTimeOriginal`, `SubSecTimeOriginal`, `OffsetTimeOriginal` |
| Live Photo | HEIC and a MOV of about 3 s | Still frame | EXIF of the still, and `com.apple.quicktime.creationdate` of the MOV |
| Video | MOV of the chosen range | Actual first frame after export | `com.apple.quicktime.creationdate` of the MOV |

**Common**

- Save with `PHAssetCreationRequest`, setting `creationDate` to the calculated time.
- Request add-only permission (`.addOnly`); do not ask to read the library.
- Put `DJI` and `Osmo Action 6` in the EXIF make and model.

**Photo**

- Get the frame at the position with `AVAssetImageGenerator` tolerances set to 0.
- Keep the original resolution; orient according to the video's rotation.

**Live Photo**

- [Link the still and the video with a shared ID](https://omz-software.com/forum/archive/5376_create-and-save-live-photo-to-camera-roll.html):
  MakerNote tag 17 in the still, `com.apple.quicktime.content.identifier` in the MOV.
- Mark the still frame position with `com.apple.quicktime.still-image-time` timed metadata.
- If the range runs past the start or end of the video, trim it and adjust the still frame
  position.
- [It may not work as a live wallpaper](https://developer.apple.com/forums/thread/798044); not
  supported in the first version.

**Video**

| Mode | Processing | Characteristics |
| --- | --- | --- |
| Lossless (default) | Passthrough export | Fast. The start may move to a keyframe |
| Accurate | Re-encode | Cuts at the chosen frame. Slower, slightly lower quality |

Because lossless mode moves the start, the time is calculated from the actual start of the exported
file, not the chosen position.

## Failure behavior and acceptance criteria

On failure, never touch the original data on the camera and never leave partial files in Photos.

| Situation | Behavior |
| --- | --- |
| Cable pulled during export | Stop, delete temporary files, prompt to reconnect |
| Cable pulled during playback | Stop playback and return to the connect screen |
| Bookmark invalid | Choose the folder again on the connect screen |
| `creation_time` missing or invalid | Ask for the time to be entered manually before saving |
| Not enough free space on the iPhone | Show the required amount and do not start the export |
| No Photos permission | Show guidance to the Settings app |

**Acceptance criteria**

- [ ] For a normal video of a clock, the saved photo's time is within ±1 s of the time shown
- [ ] Cutting from the second file of a split recording meets the same criterion
- [ ] Saved photos sort correctly in time among photos taken with the iPhone
- [ ] Live Photos play in Photos and move on long press
- [ ] Exporting a saved photo to Files keeps the EXIF capture time and offset
- [ ] Pulling the cable during export does not crash and leaves the original data unchanged

## Implementation and development

Claude Code on the Mac can handle everything from code generation to building and fixing errors.
Initial signing setup and on-device checks with the camera connected are done by hand.

| Module | Role | How it is tested |
| --- | --- | --- |
| `CameraLibrary` | Folder selection, bookmark, video list | On device |
| `VideoMetadataReader` | `creation_time`, duration and fps | Sample video |
| `CaptureTimeCalculator` | Time calculation, independent of AVFoundation | Unit tests |
| `FrameExporter` | Photo export and EXIF writing | Simulator and device |
| `LivePhotoExporter` | HEIC and MOV generation | On device |
| `ClipExporter` | Video cutting | Simulator and device |
| `PhotoLibrarySaver` | Saving to Photos | On device |

**Division of work**

| Task | Done by |
| --- | --- |
| Generating and fixing Swift code and tests | Claude Code |
| Building, running in the simulator, fixing from logs | Claude Code |
| Adding the free Apple ID to Xcode, choosing the Team | By hand |
| Enabling Developer Mode on the iPhone, trusting the developer | By hand |
| Connecting the camera, acceptance checks | By hand |

**Tooling**

- `xcodebuild` and `xcrun devicectl`
  [run without opening the Xcode UI](https://flaviocopes.com/install-iphone-apps/), so Claude Code
  can call them directly.
- [XcodeBuildMCP](https://sharedcontext.ai/plugins/external/getsentry/xcodebuildmcp) gives
  structured building, device installs and log capture. On device it
  [relies on signing set up in Xcode](https://mcp.directory/blog/xcodebuildmcp-complete-guide-2026).
- Xcode 26.3 and later also have
  [Apple's own MCP bridge](https://blakecrosley.com/de/blog/xcode-mcp-claude-code).

**Notes for a free account**

- Do the first build and install from the Xcode UI. Command-line signing with a free account is
  [described as impossible](https://skills.sh/daymade/claude-code-skills/developing-ios-apps) in some
  sources and [reported working](https://github.com/killvxk/Peepo) in others; it cannot be settled
  until tried.
- The app [expires after 7 days and must be reinstalled](https://developer.apple.com/support/compare-memberships/jp/).
- Fix the bundle ID up front. Free accounts can create only a limited number of App IDs per 7 days.

**Debugging with the camera connected**

The camera occupies the iPhone's USB-C port, so connect to the Mac
[over the network](https://flaviocopes.com/install-iphone-apps/) instead. For cases where logs
cannot be captured, the app also has its own log screen.

**Development order**

1. Check the sample video and record the results in `docs/findings.md`
2. Create the project in Xcode and install an empty app on the device with the free Team
3. Build `CaptureTimeCalculator` with unit tests
4. Get photo cutting and saving working with a sample video stored on the iPhone
5. Implement folder selection and the list over USB
6. Add Live Photo and video cutting
7. Check the acceptance criteria on device

**Open questions**

- [ ] Whether to fix the Live Photo length at 3 s
- [ ] How to convert colors when making photos from HDR or 10-bit video
