 <p align="center">
  <img src="https://github.com/user-attachments/assets/54ca4b30-b1fe-4089-88b5-b7c9f56ecad7" alt="DropWheel App Icon" width="160" />
</p>

<h1 align="center">DropWheel</h1>

<p align="center">
  <strong>A radial file conversion toolkit for macOS.</strong>
  <br />
  Convert, compress, and manage files through a simple interactive wheel.
</p>

<p align="center">
  <a href="https://github.com/kunaltelangi/DropWheel/raw/refs/heads/main/build/DropWheel.dmg">
    <strong>Download for macOS</strong>
  </a>
</p>

---

## Overview

**DropWheel** is a radial file conversion application designed for macOS. It provides a quick way to access common file operations without navigating through multiple applications or complicated menus.

Activate the wheel using **Fn** or **⌥ Space**, drag and drop your files, and select the operation you need.

The application packages its required command-line tools, so most features work without installing additional dependencies.

## Features

### Image Processing
- Convert between JPG, PNG, HEIC, WebP, TIFF, and PDF.
- Resize, shrink, and rotate images.
- Remove EXIF metadata and GPS information.
- Compress images to a specified file size.

### Video Processing
- Compress videos and convert to 720p.
- Support for H.265 encoding.
- Convert between MP4, MOV, MKV, WebM, and GIF.
- Extract audio as MP3.
- Mute videos and capture individual frames.

### Audio Processing
- Convert between MP3, M4A, WAV, FLAC, OGG, OPUS, and AIFF.
- Normalize audio levels.
- Compress audio files.

### PDF Tools
- Lossless, smart, and strong compression.
- Convert PDF documents to TXT.
- Split and merge PDF files.
- Export all pages as JPG images.
- Remove owner-password restrictions.
- Convert to grayscale and rotate pages.

### Document Conversion
- Support for DOCX, ODT, TXT, RTF, HTML, EPUB, and Markdown.
- Convert between supported document formats.

### Archive Extraction
- Extract ZIP, TAR, 7z, and RAR archives.

### Additional Capabilities
- **Set Size:** Target an exact KB or MB file size for supported image, video, audio, and PDF operations.
- **Batch Processing:** Process multiple files in one operation.
- **Flexible Output:** Save results alongside the original files or choose a different destination.
- **Original File Protection:** Original files are never overwritten.

## Installation

1. Download [`DropWheel.dmg`](https://github.com/kunaltelangi/DropWheel/raw/refs/heads/main/build/DropWheel.dmg).
2. Open the downloaded DMG file.
3. Drag **DropWheel** into your Applications folder.
4. Right-click the application and select **Open**. Confirm **Open** again when prompted.
5. Grant the requested **Accessibility** and **Input Monitoring** permissions.
6. Launch DropWheel and use **Fn** or **⌥ Space** to activate the wheel.

**First launch:** DropWheel is not notarized by Apple. If macOS blocks the application, go to **System Settings → Privacy & Security → Open Anyway**.

## Optional Dependencies

Most functionality is available through the tools bundled with the application. A few additional operations require separately installed software.

| Functionality | Dependency |
|---|---|
| Spreadsheet, presentation, and Office-to-PDF conversion | [LibreOffice](https://www.libreoffice.org) |
| PDF Optical Character Recognition (OCR) | `ocrmypdf` |

Install OCR support using Homebrew:

```bash
brew install ocrmypdf
```

DropWheel will notify you if an optional dependency is unavailable.

## Build from Source

### Requirements

- macOS
- Xcode or Xcode Command Line Tools
- [Homebrew](https://brew.sh)

Install Command Line Tools if required:

```bash
xcode-select --install
```

### Build

Clone the repository:

```bash
git clone https://github.com/kunaltelangi/DropWheel.git
cd DropWheel
```

Build the application:

```bash
# Recommended: bundle required tools and generate a DMG
./make-app.sh

# Alternative: use tools already installed on the Mac
./make-app.sh --no-bundle
```

The generated application and DMG are placed in the `build` directory.

**Architecture:** Bundled tools are built for the architecture of the Mac used to create the application. Build on Apple Silicon for Apple Silicon distribution, or on Intel for Intel distribution.

## Permissions

DropWheel requires the following macOS permissions for its global keyboard shortcuts:

- **Accessibility:** Allows the application to respond to global interactions.
- **Input Monitoring:** Required for detecting the Fn / ⌥ Space shortcuts.

If permissions need to be granted again after an update, check that you are running the application from `/Applications`. Rebuilding the application with a different code signature may also require reauthorizing permissions.

## Important Notes

- DropWheel is not distributed through the Mac App Store because its operation requires disabling App Sandbox to execute its bundled tools.
- The PDF **Unlock** operation removes owner-password restrictions such as printing, copying, and editing restrictions. It does not open documents that require a password to view.

## License

DropWheel is released under the **MIT License**. See [`LICENSE`](LICENSE) for details.

Third-party bundled tools are distributed under their respective licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

---

<p align="center">
  <sub>Built for macOS · Open Source · MIT License</sub>
</p>
