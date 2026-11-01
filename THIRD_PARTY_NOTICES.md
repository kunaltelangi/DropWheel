# Third-Party Notices

DropWheel is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).
See the [README](README.md) for an overview of the project. That license applies **only** to DropWheel's own source code. It does not apply to,
and does not modify the terms of, any third-party software listed in this document.

## Contents

- [How third-party software is used](#how-third-party-software-is-used)
- [Components bundled in `DropWheel.dmg`](#components-bundled-in-dropwheeldmg)
- [Libraries linked into bundled tools](#libraries-linked-into-bundled-tools)
- [Tools used if installed by the user (not bundled)](#tools-used-if-installed-by-the-user-not-bundled)
- [Apple system software](#apple-system-software)
- [License-specific notes](#license-specific-notes)
- [Source code availability](#source-code-availability)
- [Complete license texts](#complete-license-texts)
- [Maintainer checklist](#maintainer-checklist)

## How third-party software is used

DropWheel does not link against any of the programs below. It launches them as
separate child processes (`Foundation.Process`), passes arguments on the command line,
and reads their output. Each program is distributed as an independent, unmodified
executable and remains under its own license. Bundling these executables alongside
DropWheel in one disk image is mere aggregation; it does not make DropWheel a derivative
work of them, nor them of DropWheel.

Bundled executables are placed in `DropWheel.app/Contents/Resources/bin/`.

> This document is provided for transparency and is not legal advice.

## Components bundled in `DropWheel.dmg`

| Component | Used for | License | Upstream |
|---|---|---|---|
| FFmpeg, FFprobe | Video and audio conversion, compression, WebP encoding, duration probing | LGPL-2.1-or-later, or GPL-2.0-or-later when built with `--enable-gpl` (see [FFmpeg build](#ffmpeg-build)) | https://ffmpeg.org |
| Ghostscript | PDF compression, text extraction, page rendering, grayscale conversion | AGPL-3.0 | https://ghostscript.com |
| qpdf | PDF merge, split, rotate, decrypt, lossless recompression | Apache-2.0 | https://github.com/qpdf/qpdf |
| Pandoc | Markdown and document format conversion | GPL-2.0-or-later | https://pandoc.org |
| 7-Zip (`7zz`) | 7Z and RAR extraction | LGPL-2.1-or-later, with the unRAR license restriction; some files BSD-3-Clause | https://www.7-zip.org |
| ExifTool | Metadata removal ("Clean Info") | Artistic License (Perl) or GPL-1.0-or-later, at your option | https://exiftool.org |

Version numbers and build identifiers for each bundled binary are recorded in
[`build/BUNDLED_VERSIONS.txt`](build/BUNDLED_VERSIONS.txt).

## Libraries linked into bundled tools

The bundled executables may statically or dynamically include the following libraries.
Their licenses apply to the corresponding portions of the distributed binaries.

| Library | Used by | License | Upstream |
|---|---|---|---|
| x264 | FFmpeg (H.264 encoding) | GPL-2.0-or-later | https://www.videolan.org/developers/x264.html |
| x265 | FFmpeg (H.265/HEVC encoding) | GPL-2.0-or-later | https://www.videolan.org/developers/x265.html |
| libvpx | FFmpeg (VP9 / WebM) | BSD-3-Clause | https://chromium.googlesource.com/webm/libvpx |
| libwebp | FFmpeg (WebP) | BSD-3-Clause | https://chromium.googlesource.com/webm/libwebp |
| LAME (libmp3lame) | FFmpeg (MP3 encoding) | LGPL-2.0-or-later | https://lame.sourceforge.io |
| libvorbis, libogg | FFmpeg (OGG Vorbis) | BSD-3-Clause | https://xiph.org |
| Opus (libopus) | FFmpeg (OPUS) | BSD-3-Clause | https://opus-codec.org |
| FLAC (libFLAC) | FFmpeg (FLAC) | BSD-3-Clause | https://xiph.org/flac |

> The exact list depends on how the bundled FFmpeg was configured. Run
> `ffmpeg -buildconf` on the shipped binary and `otool -L` on each executable, and
> update this table to match.

## Tools used if installed by the user (not bundled)

DropWheel detects and invokes these only when the user has installed them. They are not
redistributed by this project.

| Tool | Used for | License | Upstream |
|---|---|---|---|
| LibreOffice | Office, spreadsheet, and slide conversion; PDF to DOCX fallback | MPL-2.0 | https://www.libreoffice.org |
| OCRmyPDF | PDF OCR | MPL-2.0 | https://github.com/ocrmypdf/OCRmyPDF |
| pdf2docx | Higher-fidelity PDF to DOCX | GPL-3.0 | https://github.com/ArtifexSoftware/pdf2docx |
| Python 3 | JSON pretty-print and minify | PSF License | https://www.python.org |

## Apple system software

`sips`, `textutil`, `ditto`, `tar`, and the system frameworks DropWheel uses
(SwiftUI, AppKit, Vision, PDFKit, ImageIO, CoreImage, CryptoKit, ServiceManagement,
ApplicationServices), which power OCR, background removal, checksums, and image compression, are
provided by macOS under Apple's license terms. They are not redistributed with
DropWheel.

## License-specific notes

### FFmpeg build

FFmpeg is LGPL-2.1-or-later by default. Enabling GPL components such as x264 or x265
(`--enable-gpl`) makes the resulting FFmpeg binary GPL-2.0-or-later. The binary shipped
in `DropWheel.dmg` was built with the following configuration:

```
<paste the output of: ffmpeg -buildconf>
```

If any source in the FFmpeg build was patched, the patches are published in
[`third_party/patches/`](third_party/patches/).

### Ghostscript (AGPL-3.0)

Ghostscript is licensed under the GNU Affero General Public License v3. The
corresponding source for the exact bundled version is available from the upstream
project and is offered under [Source code availability](#source-code-availability).
DropWheel does not expose Ghostscript over a network.

### 7-Zip and unRAR

The RAR extraction code in 7-Zip is subject to the unRAR license restriction: it may not
be used to recreate the RAR compression algorithm. DropWheel uses 7-Zip for extraction
only.

### Pandoc, x264, x265 (GPL)

These are distributed under the GPL. They are run as separate programs; DropWheel's own
code is not combined with them into a single work.

## Source code availability

For every bundled component licensed under the GPL, LGPL, or AGPL, the complete
corresponding source code for the exact version we ship is available:

1. From the upstream project, using the links in the tables above and the version
   recorded in `build/BUNDLED_VERSIONS.txt`; and
2. On request, for at least three years from the date of each release, by opening an
   issue at https://github.com/kunaltelangi/DropWheel/issues.

Any modifications we have made to these components, along with the build scripts used to
produce the shipped binaries, are published in this repository under `third_party/`.

## Complete license texts

Full license texts for each bundled component are available from the upstream links
above and are included in the application bundle at:

```
DropWheel.app/Contents/Resources/Licenses/
```

## Maintainer checklist

Complete this before every release:

- [ ] Confirm the table of bundled components matches what `make-app.sh` copies into
      `Contents/Resources/bin/`.
- [ ] Record each binary's version in `build/BUNDLED_VERSIONS.txt`.
- [ ] Paste the real `ffmpeg -buildconf` output into [FFmpeg build](#ffmpeg-build).
- [ ] Run `otool -L` on every bundled executable and update the linked-library table.
- [ ] Copy each component's license text into `Resources/Licenses/`.
- [ ] Publish any patches or custom build scripts under `third_party/`.
- [ ] Keep `assets/AppIcon.svg` / `AppIcon.png` in sync with the icon generated by `make-app.sh`.
- [ ] Remove this checklist from the published copy if you prefer, once complete.
