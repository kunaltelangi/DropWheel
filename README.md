<p align="center">
  <img src="https://github.com/user-attachments/assets/54ca4b30-b1fe-4089-88b5-b7c9f56ecad7" alt="DropWheel App Icon" width="160" />
</p>

<h1 align="center">DropWheel</h1>

<p align="center">
  <strong>A radial file conversion and compression toolkit for macOS.</strong>
  <br />
  Press a hotkey, drop files on the wheel, pick an action. Done.
</p>

<p align="center">
  <a href="https://github.com/kunaltelangi/DropWheel/raw/refs/heads/main/build/DropWheel.dmg"><strong>Download for macOS</strong></a>
  &nbsp;·&nbsp;
  <a href="docs/FEATURES.md"><strong>Full feature reference</strong></a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" />
  <img alt="Language" src="https://img.shields.io/badge/Swift-5-orange" />
  <img alt="UI" src="https://img.shields.io/badge/UI-SwiftUI-blue" />
  <img alt="License" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-orange" />
</p>

---

## Table of Contents

- [Overview](#overview)
- [Highlights](#highlights)
- [Supported Operations](#supported-operations)
- [Installation](#installation)
- [Usage](#usage)
- [Settings](#settings)
- [Optional Dependencies](#optional-dependencies)
- [Permissions](#permissions)
- [Build from Source](#build-from-source)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Overview

DropWheel is a menu bar utility that puts the everyday file operations (convert, compress, resize, merge, split, extract) behind a single radial menu. It removes the need to open a separate app, website, or terminal for each small job.

1. Press **Fn** or **⌥ Space** anywhere in macOS.
2. A wheel appears centered on the screen your cursor is on.
3. Drag one or more files onto it.
4. The wheel shows only the actions that make sense for that file type. Click one, or press its number key.

All processing runs **locally** on your Mac using native macOS frameworks and battle-tested command-line tools (FFmpeg, Ghostscript, qpdf, Pandoc, and others). Files are never uploaded anywhere.

## Highlights

- **Context-aware wheel.** The wedges change with the dropped file type: images, video, audio, PDF, documents, Markdown, spreadsheets, slides, archives, and JSON.
- **Set Size.** Compress an image, video, audio file, or PDF to a target size you choose (for example, "under 500 KB").
- **Batch processing.** Drop many files of the same type and run one action across all of them.
- **Non-destructive.** Originals are never overwritten. Outputs get a suffix and a unique name. Optionally move originals to Trash after a successful conversion.
- **Keyboard-first.** Open with a hotkey, choose with `1`–`9` / `0`, close with `Esc`.
- **Self-contained.** The packaged app bundles its CLI tools, so most features work with zero installs.
- **Cancellable.** Click the center of the wheel during a job to stop it immediately.
- **Smart no-op.** Compression actions that would not make the file smaller keep your original and tell you so.

## Supported Operations

A quick summary. See [docs/FEATURES.md](docs/FEATURES.md) for every action, the exact settings it uses, and its output naming.

| Input type | Operations |
|---|---|
| **Images** (JPG, PNG, HEIC, WebP, TIFF, GIF, BMP, and more) | Set Size · convert to JPG / PNG / HEIC / WebP / PDF / TIFF · Strip metadata · Rotate · Shrink · Resize to 1080 |
| **Video** (MP4, MOV, MKV, AVI, WebM, and more) | Set Size · Compress · 720p · H.265 · convert to MP4 / MOV / MKV / WebM / GIF · Extract MP3 · Mute · Grab first frame as PNG |
| **Audio** (MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, and more) | Set Size · convert to MP3 / M4A / WAV / FLAC / OGG / OPUS / AIFF · Normalize · Compress |
| **PDF** | Set Size · Lossless / Smart / Strong compression · To DOCX · To TXT · Split · All Pages to JPG · Unlock · Grayscale · Rotate · OCR · Merge (multiple PDFs) |
| **Documents** (DOC, DOCX, RTF, TXT, HTML, ODT) | Convert to DOCX / DOC / PDF / TXT / RTF / HTML / ODT / Markdown / EPUB |
| **Markdown** | Convert to DOCX / ODT / HTML / EPUB / RTF / TXT |
| **Spreadsheets** (XLS, XLSX, ODS, CSV, TSV) | Convert to PDF / XLSX / CSV / ODS / HTML |
| **Slides** (PPT, PPTX, ODP) | Convert to PDF / PPTX / ODP, export slide 1 as PNG |
| **Archives** (ZIP, TAR, GZ, TGZ, BZ2, XZ, 7Z, RAR) | Extract |
| **JSON** | Pretty-print · Minify · Zip |
| **Anything else, including folders** | Zip |

## Installation

1. Download [`DropWheel.dmg`](https://github.com/kunaltelangi/DropWheel/raw/refs/heads/main/build/DropWheel.dmg).
2. Open the DMG and drag **DropWheel** into your **Applications** folder.
3. Right-click the app, choose **Open**, and confirm **Open** again when prompted.
4. Grant the requested **Accessibility** and **Input Monitoring** permissions.
5. Press **Fn** or **⌥ Space** to bring up the wheel.

> **First launch:** DropWheel is not notarized by Apple. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**.

**Requirements:** macOS 14 (Sonoma) or later.

## Usage

### The basic flow

1. **Open** the wheel with **Fn** or **⌥ Space** (or the menu bar icon → *Show Wheel*).
2. **Drop** one or more files onto the wheel.
3. **Pick** an action by clicking a wedge or pressing its number.
4. **Wait** for the center to show a checkmark. The result is revealed in Finder automatically, and the wheel closes itself.

### Wedge colors

| Color | Meaning |
|---|---|
| Neutral / blue on hover | A **conversion** or utility action |
| Green | A **compression** action (output is guaranteed not to be larger than the input) |

### Keyboard shortcuts

| Key | Action |
|---|---|
| `Fn` or `⌥ Space` | Open / close the wheel |
| `1` – `9`, `0` | Run the 1st–9th action, or `0` for the 10th |
| `H` or `/` | Toggle the help card |
| `Esc` | Go back (from the Set Size card) or close the wheel |
| Click wheel center | Cancel a running job, or return to the idle state |

### Multiple files

- All dropped files are processed with the same action, in filename order.
- The wheel is built from the **first file's type**. Files of a different type are skipped, and the result note tells you how many were skipped.
- Dropping two or more PDFs adds a **Merge** action as the first wedge.

## Settings

Everything lives in the menu bar icon:

| Setting | Description |
|---|---|
| **Launch at login** | Registers DropWheel as a login item. |
| **Move original to Trash after converting** | After a successful run the source file is moved to Trash (never permanently deleted). Not applied to Merge or to actions that output a folder. |
| **Play sound when done** | Glass on success, Funk on warning, Basso on failure. |
| **Save results in…** | Choose a fixed output folder. |
| **Save results next to original** | Reset to the default behavior. |
| **Accessibility / Input Monitoring permission…** | Shortcuts to the matching System Settings panes. |
| **Keyboard settings (stop emoji on fn)…** | Opens Keyboard settings so you can stop the Fn key from triggering the emoji picker. |
| **How it works…** | Shows the in-app help card. |

## Optional Dependencies

The packaged app bundles most tools. A few features rely on third-party software that you install yourself:

| Feature | Dependency | Install |
|---|---|---|
| Office-to-PDF, spreadsheet, and slide conversion (and PDF → DOCX fallback) | [LibreOffice](https://www.libreoffice.org) | Download from libreoffice.org, install to `/Applications` |
| PDF OCR | `ocrmypdf` | `brew install ocrmypdf` |
| Higher-fidelity PDF → DOCX | `pdf2docx` | `pipx install pdf2docx` (used automatically if found) |
| JSON Pretty / Minify | `python3` | Included with Xcode Command Line Tools |

DropWheel shows a clear message in the wheel if a required tool is missing.

## Permissions

| Permission | Why it is needed |
|---|---|
| **Accessibility** | Lets the app observe the global Fn / ⌥ Space shortcuts. The system prompt is shown once. |
| **Input Monitoring** | Required by macOS for detecting modifier-key events (Fn) outside the app. |

macOS ties these grants to the app's code signature and location. If they stop working after an update, run the app from `/Applications`, then remove and re-add it under **Privacy & Security**.

## Build from Source

### Requirements

- macOS 14+
- Xcode or Xcode Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh)

### Steps

```bash
git clone https://github.com/kunaltelangi/DropWheel.git
cd DropWheel

# Recommended: bundle the required tools and produce a DMG
./make-app.sh

# Alternative: use tools already installed on this Mac
./make-app.sh --no-bundle
```

Output goes to the `build/` directory.

> **Architecture:** Bundled tools are built for the Mac that runs the script. Build on Apple Silicon to ship for Apple Silicon, and on Intel to ship for Intel.

### Project settings

- Swift 5 language mode
- Deployment target: macOS 14
- **App Sandbox: OFF.** The app must launch bundled and system command-line tools, which the sandbox forbids. This is also why DropWheel is not on the Mac App Store.

## How It Works

DropWheel is a SwiftUI app with a small AppKit layer for the global behavior.

| Layer | Responsibility |
|---|---|
| **App / menu bar** | `MenuBarExtra` UI, persistent settings via `@AppStorage` / `UserDefaults`, login item via `SMAppService`. |
| **AppDelegate + `WheelPanel`** | A borderless, non-activating floating `NSPanel` that appears on all Spaces. Global and local `NSEvent` monitors handle Fn, ⌥ Space, Esc, and number keys. |
| **Action catalog** | `kind(of:)` classifies each file; `actions(for:)` returns a list of `WheelAction` values. Each action declares its tool, arguments, output extension, suffix, and flags. |
| **Runner** | `runTool` launches tools as child `Process`es with a prepared `PATH`, captures output, and supports cancellation through a thread-safe `Job`. `convert` handles temp directories, unique output names, and the "no gain" check. |
| **Target-size engine** | Dedicated compressors per media type (ImageIO, Ghostscript, two-pass FFmpeg) that search for the best quality at or below the target. |
| **Wheel UI** | A state machine (`idle`, `help`, `choosing`, `sizing`, `running`, `done`, `failed`) renders wedges, hit-testing, hover, and the Set Size card. |

Tool lookup order: absolute path → tools bundled in the app (`Resources/bin`) → `/usr/bin`, `/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`.

## Troubleshooting

**The wheel doesn't open when I press Fn.**
Confirm Accessibility and Input Monitoring are granted (menu bar → permission shortcuts). Make sure the app runs from `/Applications`. Use **⌥ Space** as a fallback.

**Pressing Fn opens the emoji picker.**
Open *Keyboard settings* from the menu and set the globe/Fn key action to **Do Nothing**.

**"Needs LibreOffice".**
Install LibreOffice into `/Applications`. DropWheel looks for `/Applications/LibreOffice.app`.

**OCR says a tool isn't included.**
Run `brew install ocrmypdf`.

**"Already optimal" or the output equals the input.**
The compressor could not make the file smaller, so the original was kept.

**"Target not reachable".**
The requested size is below what is practical for that file. The smallest result found was still saved. See [Set Size](docs/FEATURES.md#set-size-target-size-compression).

**Permissions reset after I rebuilt the app.**
A different code signature is treated as a new app by macOS. Re-grant the permissions.

## Known Limitations

- Not notarized, so the first launch requires the Open Anyway flow.
- Not sandboxed and therefore not eligible for the Mac App Store.
- Only files of the **same type as the first dropped file** are processed in a batch.
- *Strip Info* is limited to JPG, PNG, and WebP inputs.
- *Unlock* removes owner-password restrictions only. It cannot open files that need a password to view.
- Set Size always outputs a fixed format per type (JPG, MP4, MP3, PDF).
- Video *Frame→PNG* exports the first frame only.

## Contributing

Issues and pull requests are welcome.

1. Fork the repo and create a feature branch.
2. Build with `./make-app.sh --no-bundle` for a fast iteration loop.
3. To add a new action, add a `WheelAction` to the relevant case in `actions(for:)`, using the helper constructors (`ff`, `sips`, `gs`, `lo`, `pd`, `textutil`) where possible.
4. Test with a single file, a batch, and a missing-tool scenario.
5. Open a PR describing the change and the file types you tested.

## License

DropWheel is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE).

- **Allowed, free of charge:** personal use, hobby projects, study and research, and use by charities, schools, public research bodies, and government institutions. You may also modify and share it for these purposes.
- **Not allowed without permission:** any commercial use, such as using it for paid work in a business, bundling it into a paid product, or selling it.
- **Commercial licensing:** to request permission, open an issue on this repository.

This is not an OSI-approved open source license.

Bundled third-party tools are distributed under their own licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

---

<p align="center">
  <sub>Built for macOS · Source-available · PolyForm Noncommercial 1.0.0</sub>
</p>
