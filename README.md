<p align="center">
  <img
    src="https://github.com/user-attachments/assets/54ca4b30-b1fe-4089-88b5-b7c9f56ecad7"
    alt="DropWheel App Icon"
    width="160"
  />
</p>

# DropWheel

A radial file converter for macOS. Press **fn** or **⌥Space**, drop files onto the wheel, click a wedge. Done.

**Nothing else to install.** The tools it needs are packed inside the app.

[**Download for macOS**]([https://github.com/YOUR_USERNAME/DropWheel/releases/latest/download/DropWheel.dmg](https://github.com/kunaltelangi/DropWheel/releases/latest/download/DropWheel.dmg))

## Install

1. Download `DropWheel.dmg` and open it.
2. Drag **DropWheel** onto **Applications**.
3. Right-click DropWheel in Applications → **Open** → **Open** (first launch only, because the app is not notarized by Apple).
   If macOS still blocks it: System Settings → Privacy & Security → **Open Anyway**.
4. Allow **Accessibility** and **Input Monitoring** when asked (needed for the fn / ⌥Space shortcut).
5. Press **fn** or **⌥Space**, drop a file, click a wedge.

## Features

- **Set Size**: compress an image, video, audio file or PDF to an exact KB / MB limit
- **Images**: JPG, PNG, HEIC, WebP, TIFF, PDF, rotate, shrink, resize, strip EXIF/GPS info
- **Video**: compress, 720p, H.265, MP4/MOV/MKV/WebM/GIF, extract MP3, mute, grab a frame
- **Audio**: MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, normalize, compress
- **PDF**: compress (lossless / smart / strong), to TXT, split, merge, all pages to JPG, unlock, grayscale, rotate
- **Documents / Markdown**: DOCX, ODT, TXT, RTF, HTML, EPUB, MD
- **Archives**: extract zip, tar, 7z, rar
- Batch: drop many files at once
- Results are saved next to the original (or a folder you choose). Originals are never overwritten.

### Optional extras (not included)

These need a free program installed separately; DropWheel tells you if it is missing.

- Spreadsheet / slide / Office-to-PDF conversion: install [LibreOffice](https://www.libreoffice.org)
- PDF OCR: `brew install ocrmypdf`

## Build it yourself

Needs Xcode or Command Line Tools (`xcode-select --install`) and [Homebrew](https://brew.sh) on the building Mac only.

```
./make-app.sh              # app with tools packed inside + DMG  (recommended)
./make-app.sh --no-bundle  # small build that uses tools installed on the Mac
```

The result is in the `build` folder.

> The packed tools match the Mac that builds the app (Apple Silicon or Intel). Build on an Apple Silicon Mac for Apple Silicon users.

## Permissions

- **Accessibility** and **Input Monitoring**: needed for the global fn / ⌥Space shortcut.
- If macOS asks again after every update, the app was rebuilt with a different signature. Run it from `/Applications`.

## Notes

- Not on the Mac App Store, because it needs the sandbox off to run its tools.
- "Unlock" only removes owner-password restrictions (print/copy/edit). It cannot open a PDF that needs a password to view.

## License

DropWheel is MIT licensed (see `LICENSE`). The packed tools have their own licenses; see `THIRD_PARTY_NOTICES.md`.
