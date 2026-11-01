# DropWheel Feature Reference

This document describes every action DropWheel offers, how it behaves, and what it does under the hood. For installation and a quick overview, see the [README](../README.md).

## Contents

1. [Core Concepts](#core-concepts)
2. [Images](#images)
3. [Video](#video)
4. [Audio](#audio)
5. [PDF](#pdf)
6. [Documents](#documents)
7. [Markdown](#markdown)
8. [Spreadsheets](#spreadsheets)
9. [Presentations](#presentations)
10. [Archives](#archives)
11. [JSON](#json)
12. [Other Files and Folders](#other-files-and-folders)
13. [Set Size (Target-Size Compression)](#set-size-target-size-compression)
14. [Output Behavior](#output-behavior)
15. [Batch Processing](#batch-processing)
16. [Cancellation, Errors, and Feedback](#cancellation-errors-and-feedback)
17. [Tool Resolution](#tool-resolution)
18. [Action Index](#action-index)

---

## Core Concepts

### File classification

When files are dropped, DropWheel classifies the **first** file by extension into one of these kinds: `image`, `video`, `audio`, `pdf`, `document`, `markdown`, `sheet`, `slides`, `archive`, `data`, or `other`. Unknown extensions fall back to the system's UTType hierarchy (anything conforming to image, movie/video, audio, or PDF is routed accordingly). Directories are always `other`.

Extension aliases are normalized (`jpeg`→`jpg`, `tif`→`tiff`, `heif`→`heic`, `htm`→`html`, `markdown`→`md`, `aif`→`aiff`).

### Wheel contents

- The wheel shows one wedge per available action, evenly dividing 360°.
- The first nine wedges display a number badge (`1`–`9`); `0` selects the 10th.
- Actions that would produce the same format as the input are hidden. For example, a PNG will not offer "To PNG". This only applies to actions without a suffix.
- **Green wedges** are compression actions. Blue (accent) is used on hover for everything else.

### Compression guarantee

Any action flagged as compression (green) is checked after it runs. If the result is **not smaller** than the input, the output is discarded, the original is left untouched, and the wheel reports "Already optimal".

---

## Images

Recognized extensions: `jpg`, `jpeg`, `png`, `heic`, `heif`, `tiff`, `tif`, `gif`, `bmp`, `webp`, `jp2`, `ico`, `psd`, plus anything the system identifies as an image.

| Action | Output | Tool | Details |
|---|---|---|---|
| **Set Size** | `.jpg` | ImageIO | Compress to a target size. See [Set Size](#set-size-target-size-compression). |
| **To JPG** | `.jpg` | `sips` | Format conversion. |
| **To PNG** | `.png` | `sips` | Format conversion. |
| **To HEIC** | `.heic` | `sips` | Format conversion. |
| **To WebP** | `.webp` | `ffmpeg` | Quality level 85. |
| **To PDF** | `.pdf` | `sips` | Wraps the image in a one-page PDF. |
| **To TIFF** | `.tiff` | `sips` | Format conversion. |
| **Strip Info** | same format, suffix `-clean` | `ffmpeg` | Removes all metadata (EXIF, GPS location, camera model, timestamps) using a lossless stream copy. **Only offered for JPG, PNG, and WebP**, because stream copy is only reliable for those. |
| **Rotate** | same format, suffix `-rotated` | `sips` | Rotates 90° clockwise. Run repeatedly for 180° / 270°. |
| **Shrink** | `.jpg`, suffix `-small` | `sips` | JPEG quality 70, longest side capped at 2400 px. Green (compression). |
| **Resize** | same format, suffix `-1080` | `sips` | Longest side scaled to 1080 px. Green (compression). |

---

## Video

Recognized extensions: `mp4`, `mov`, `mkv`, `avi`, `webm`, `m4v`, `flv`, `wmv`, `mpg`, `mpeg`, `3gp`, plus system-identified movie types. All video actions use FFmpeg.

| Action | Output | Details |
|---|---|---|
| **Set Size** | `.mp4` | Two-pass H.264 aimed at an exact size. See [Set Size](#set-size-target-size-compression). |
| **Compress** | `.mp4`, suffix `-small` | H.264, CRF 26, `fast` preset, AAC audio at 128 kbps, yuv420p. Green. |
| **720p** | `.mp4`, suffix `-720p` | Scales to 720 px height (width auto, even), then the same encode settings as Compress. Green. |
| **H.265** | `.mp4`, suffix `-hevc` | HEVC (`libx265`), CRF 28, `hvc1` tag for Apple compatibility, AAC 128 kbps. Smaller than H.264 at similar quality; slower to encode. Green. |
| **To MP4** | `.mp4` | H.264, CRF 20, AAC. High-quality re-encode. |
| **To MOV** | `.mov` | H.264, CRF 20, AAC. |
| **To MKV** | `.mkv` | Stream copy (no re-encode), so it is near-instant and lossless. |
| **To WebM** | `.webm` | VP9, CRF 32, constant-quality mode. |
| **To GIF** | `.gif` | 12 fps, 480 px wide. Best for short clips. |
| **To MP3** | `.mp3` | Extracts the audio track, VBR quality 2 (roughly 170–210 kbps). |
| **Mute** | same format, suffix `-mute` | Removes the audio track using stream copy (no re-encode). |
| **Frame→PNG** | `.png` | Exports the **first frame** of the video. |

---

## Audio

Recognized extensions: `mp3`, `m4a`, `wav`, `flac`, `ogg`, `opus`, `aac`, `aiff`, `aif`, `wma`, `caf`, plus system-identified audio types. All audio actions use FFmpeg.

| Action | Output | Details |
|---|---|---|
| **Set Size** | `.mp3` | Bitrate computed from duration to hit the target. See [Set Size](#set-size-target-size-compression). |
| **To MP3** | `.mp3` | 192 kbps. |
| **To M4A** | `.m4a` | AAC, 192 kbps. |
| **To WAV** | `.wav` | Uncompressed PCM. |
| **To FLAC** | `.flac` | Lossless compression. |
| **To OGG** | `.ogg` | Vorbis, quality 5. |
| **To OPUS** | `.opus` | Opus, 128 kbps. |
| **To AIFF** | `.aiff` | Uncompressed. |
| **Normalize** | same format, suffix `-norm` | EBU R128 loudness normalization (`loudnorm` filter). Evens out volume between tracks. |
| **Compress** | `.mp3`, suffix `-small` | 96 kbps MP3. Green. |

---

## PDF

| Action | Output | Tool | Details |
|---|---|---|---|
| **Set Size** | `.pdf` | Ghostscript | Searches for the gentlest image downsampling that meets the target. See [Set Size](#set-size-target-size-compression). |
| **Lossless** | `.pdf`, suffix `-lossless` | `qpdf` | Rebuilds object streams and recompresses Flate data at level 9. No quality loss; savings vary. Green. |
| **Smart** | `.pdf`, suffix `-small` | Ghostscript | `/prepress` preset. High quality, moderate savings. Green. |
| **Strong** | `.pdf`, suffix `-small` | Ghostscript | `/ebook` preset. Stronger compression, suitable for screen reading and email. Green. |
| **To DOCX** | `.docx` | `pdf2docx` or LibreOffice | Uses `pdf2docx` when installed, which usually gives better layout fidelity. Otherwise falls back to LibreOffice's Writer PDF import. |
| **To TXT** | `.txt` | Ghostscript | Extracts text with the `txtwrite` device. Scanned PDFs produce no text unless OCR is run first. |
| **Split** | folder `<name>-pages/` | `qpdf` | Writes every page as its own PDF (`page-*.pdf`). |
| **All Pages** | folder `<name>-images/` | Ghostscript | Renders every page as a numbered JPG (`page-001.jpg`, …) at 150 DPI, quality 90, with anti-aliased text and graphics. |
| **Unlock** | `.pdf`, suffix `-unlocked` | `qpdf` | Removes **owner-password** restrictions (printing, copying, editing). It cannot open a document that requires a password to view. |
| **Grayscale** | `.pdf`, suffix `-gray` | Ghostscript | Converts all color to grayscale. Cheaper to print and often smaller. |
| **Rotate** | `.pdf`, suffix `-rotated` | `qpdf` | Rotates every page 90° clockwise. |
| **OCR** | `.pdf`, suffix `-ocr` | `ocrmypdf` | Adds a searchable text layer to scanned pages. Pages that already contain text are skipped (`--skip-text`). Requires `brew install ocrmypdf`. |
| **Merge** | `.pdf`, suffix `-merged` | `qpdf` | Only appears when **two or more PDFs** are dropped. Combines them in filename order. Originals are never trashed after a merge. |

> `qpdf` exit code 3 (completed with warnings) is treated as success.

---

## Documents

Recognized extensions: `doc`, `docx`, `rtf`, `rtfd`, `txt`, `html`, `htm`, `odt`.

| Action | Output | Tool |
|---|---|---|
| **To DOCX** | `.docx` | `textutil` (macOS built-in) |
| **To DOC** | `.doc` | `textutil` |
| **To PDF** | `.pdf` | LibreOffice |
| **To TXT** | `.txt` | `textutil` |
| **To RTF** | `.rtf` | `textutil` |
| **To HTML** | `.html` | `textutil` |
| **To ODT** | `.odt` | `textutil` |
| **To MD** | `.md` | Pandoc |
| **To EPUB** | `.epub` | Pandoc |

---

## Markdown

Recognized extensions: `md`, `markdown`. All conversions use Pandoc in standalone mode.

| Action | Output |
|---|---|
| **To DOCX** | `.docx` |
| **To ODT** | `.odt` |
| **To HTML** | `.html` |
| **To EPUB** | `.epub` |
| **To RTF** | `.rtf` |
| **To TXT** | `.txt` |

---

## Spreadsheets

Recognized extensions: `xls`, `xlsx`, `ods`, `csv`, `tsv`. Requires **LibreOffice**.

| Action | Output |
|---|---|
| **To PDF** | `.pdf` |
| **To XLSX** | `.xlsx` |
| **To CSV** | `.csv` |
| **To ODS** | `.ods` |
| **To HTML** | `.html` |

LibreOffice runs headless with a private user profile, so conversions work even if LibreOffice is already open.

---

## Presentations

Recognized extensions: `ppt`, `pptx`, `odp`. Requires **LibreOffice**.

| Action | Output | Notes |
|---|---|---|
| **To PDF** | `.pdf` | |
| **To PPTX** | `.pptx` | |
| **To ODP** | `.odp` | |
| **Slide 1→PNG** | `.png` | Exports the first slide as an image. |

---

## Archives

Recognized extensions: `zip`, `tar`, `gz`, `tgz`, `bz2`, `xz`, `7z`, `rar`.

| Archive | Extractor | Notes |
|---|---|---|
| `.zip` | `ditto` | macOS built-in, preserves metadata. |
| `.7z`, `.rar` | `7zz` | From the `sevenzip` formula (bundled in the packaged app). |
| `.tar`, `.gz`, `.tgz`, `.bz2`, `.xz` | `tar` | macOS built-in. |

The only action is **Extract**, which creates a folder named after the archive next to it (or in your chosen output folder). If that name is taken, a numeric suffix is added.

---

## JSON

Recognized extension: `json`. Requires `python3`.

| Action | Output | Details |
|---|---|---|
| **Pretty** | same format, suffix `-pretty` | Re-indents with `json.tool`. |
| **Minify** | same format, suffix `-min` | Removes all whitespace using compact separators. |
| **Zip** | `.zip` | See below. |

---

## Other Files and Folders

Any unrecognized file type and any **folder** offers a single action:

| Action | Output | Details |
|---|---|---|
| **Zip** | `.zip` | Uses `ditto -c -k --keepParent`, so the archive contains the file or folder at its top level. |

---

## Set Size (Target-Size Compression)

Set Size is the first wedge for images, video, audio, and PDFs. Instead of guessing a quality preset, you tell DropWheel the size you need ("under 2 MB for this upload form") and it works toward it.

### The Set Size card

- **Numeric field** with a **KB / MB** switch. Units are decimal (1 MB = 1,000,000 bytes). A comma is accepted as the decimal separator.
- **Slider** that scales from 2% to 100% of the smallest dropped file.
- **Preset chips** (50 KB up to 25 MB), shown only if smaller than the file.
- **Live hint** showing the percentage reduction (`1.8 MB → 500 KB, about 72% smaller`), or "Each file will be at most …" for batches.
- **Validation:** the Compress button is enabled only when the target is at least 1 KB and smaller than the largest selected file.
- The field opens focused with a default of half the smallest file's size. `Return` starts, `Esc` goes back.

Output is saved with the suffix `-compressed`. If the file is already at or below the target, it is left as is.

### Strategy by media type

| Type | Output | Algorithm |
|---|---|---|
| **Image** | `.jpg` | Walks a ladder of resolutions (100% down to 8% of the longest side). At each step it binary-searches JPEG quality between 0.5 and 0.92 for the highest quality that fits. Quality is never dropped below 0.5 until resolution options run out. As a last resort it tries quality 0.3, 0.15, and 0.05 at the smallest resolution. Transparency is flattened onto white. EXIF orientation is applied. |
| **PDF** | `.pdf` | Runs Ghostscript with image downsampling at 250, 200, 150, 120, 96, 72, 55, and 40 DPI. It first tries the strongest setting; if that cannot meet the target, it stops. Otherwise it binary-searches for the **gentlest** DPI that still fits. Text-only PDFs may not shrink much because there are no images to downsample. |
| **Video** | `.mp4` | Probes duration and audio presence, then computes a bitrate from the target (with a 7% safety margin). Resolution is capped by bitrate: ≥3 Mbps no cap, ≥1.2 Mbps 1080p, ≥500 kbps 720p, ≥220 kbps 480p, otherwise 360p. Audio gets about 12% of the budget, clamped to 32–128 kbps. Uses **two-pass** H.264 for accuracy and retries up to twice with a corrected bitrate if the first result overshoots. |
| **Audio** | `.mp3` | Computes the bitrate from duration (4% safety margin), clamped to 24–320 kbps. Below 64 kbps it also drops the sample rate to 22.05 kHz, and below 48 kbps it switches to mono. Retries once if the first result is too large. |

### When the target cannot be met

If even the most aggressive settings produce a file larger than the target, DropWheel saves the **smallest result it achieved** and shows a warning: *"Target not reachable"*. If no result is smaller than the original, the original is kept.

---

## Output Behavior

### Naming

Output name = `<original name><suffix>.<new extension>`. Examples: `photo-clean.jpg`, `report-small.pdf`, `movie-720p.mp4`.

If the file already exists, a counter is appended instead of overwriting: `photo-clean 2.jpg`, `photo-clean 3.jpg`, and so on. **Originals are never overwritten.**

### Location

- Default: next to the original file.
- If you set **Save results in…**, all results go to that folder (it is validated at run time and falls back to the original's folder if the folder disappears).

### Trash after converting

With **Move original to Trash after converting** enabled, the source file is moved to the Trash (recoverable) after a successful run. It is **skipped** when:

- the action was **Merge**,
- the output is a **folder** (Split, All Pages, Extract),
- the action made no change (original kept).

### After a run

- The result is revealed in Finder automatically.
- The wheel shows a summary (new size, or `before → after` for compression) and closes itself after about 2.2 seconds (4 seconds when there is a warning).
- Optional sound: *Glass* (success), *Funk* (warning), *Basso* (failure).

---

## Batch Processing

- Drop multiple files and run one action over all of them sequentially. Progress is shown as `Action 2/5`.
- The wheel's actions come from the **first file** (sorted by filename). Files whose type differs from the first file are skipped and counted in the result note (`N skipped (other type)`).
- Failures do not stop the batch. The summary reports how many failed.
- For Set Size on a batch, every file is compressed to *at most* the target size individually.
- Dropping several PDFs adds **Merge**, which combines them into one file instead of processing them individually.

---

## Cancellation, Errors, and Feedback

| Situation | Behavior |
|---|---|
| **Cancel** | Click the center of the wheel while it is running. The running child process is terminated immediately and partial output is removed. |
| **Missing tool** | The center shows an actionable message, such as "Needs LibreOffice" or `brew install <formula>` for developer builds without bundled tools. |
| **Tool error** | The last non-empty line of the tool's error output (trimmed to 90 characters) is displayed. Tap the center to retry. |
| **Partial success** | Shows an orange warning with counts for unreachable targets, failures, and skipped files. |
| **Busy** | Drops and hotkeys that would reset state are ignored while a job is running. |

---

## Tool Resolution

Tools are located in this order:

1. An absolute path (used for LibreOffice at `/Applications/LibreOffice.app/Contents/MacOS/soffice`).
2. The app's bundled tools folder (`DropWheel.app/Contents/Resources/bin`).
3. System locations: `/usr/bin`, `/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`.

Child processes run with a `PATH` that prefers the bundled folder, and with `GS_LIB` pointed at the bundled Ghostscript resources when present, so the packaged Ghostscript works without a system install.

| Tool | Used for | Source |
|---|---|---|
| `sips`, `textutil`, `ditto`, `tar`, `sh` | Image conversion, document conversion, zip, extraction | macOS built-in |
| `ffmpeg`, `ffprobe` | Video, audio, WebP, metadata stripping | Bundled |
| `gs` (Ghostscript) | PDF compression, TXT, page images, grayscale | Bundled |
| `qpdf` | Lossless compression, split, merge, unlock, rotate | Bundled |
| `pandoc` | Markdown and document conversions | Bundled |
| `7zz` | 7z and RAR extraction | Bundled |
| LibreOffice | Office conversions, PDF → DOCX fallback | User-installed |
| `ocrmypdf` | OCR | User-installed |
| `pdf2docx` | Better PDF → DOCX | User-installed (optional) |
| `python3` | JSON Pretty / Minify | Xcode Command Line Tools |

---

## Action Index

Quick lookup of every action by name.

| Action | Applies to |
|---|---|
| All Pages | PDF |
| Compress | Video, Audio |
| Extract | Archives |
| Frame→PNG | Video |
| Grayscale | PDF |
| H.265 | Video |
| Lossless | PDF |
| Merge | Multiple PDFs |
| Minify | JSON |
| Mute | Video |
| Normalize | Audio |
| OCR | PDF |
| Pretty | JSON |
| Resize | Image |
| Rotate | Image, PDF |
| Set Size | Image, Video, Audio, PDF |
| Shrink | Image |
| Slide 1→PNG | Presentations |
| Smart / Strong | PDF |
| Split | PDF |
| Strip Info | Image (JPG, PNG, WebP) |
| To `<format>` | Images, Video, Audio, Documents, Markdown, Spreadsheets, Presentations, PDF (DOCX, TXT) |
| Unlock | PDF |
| Zip | JSON, other files, folders |
| 720p | Video |
