# Third-Party Notices

DropWheel itself is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE).

The packaged `DropWheel.dmg` also ships separate command-line programs. They run as independent processes (DropWheel launches them; it does not link against them) and remain under their own licenses. Each project's full license text and source code are available from the upstream links below.

> **Maintainer note:** Verify this list against what `make-app.sh` actually bundles, and against the exact versions and build options you used (especially FFmpeg). Update the table if anything differs.

| Tool | Used for | License | Source |
|---|---|---|---|
| FFmpeg / FFprobe | Video and audio conversion, WebP, metadata stripping | LGPL 2.1+ or GPL 2+ depending on build options (builds with libx264 / libx265 are GPL) | https://ffmpeg.org |
| x264 | H.264 encoding (inside FFmpeg) | GPL 2+ | https://www.videolan.org/developers/x264.html |
| x265 | H.265 encoding (inside FFmpeg) | GPL 2+ | https://www.videolan.org/developers/x265.html |
| Ghostscript | PDF compression, text extraction, page images, grayscale | AGPL 3 | https://ghostscript.com |
| qpdf | PDF merge, split, rotate, unlock, lossless compression | Apache 2.0 | https://github.com/qpdf/qpdf |
| Pandoc | Markdown and document conversion | GPL 2+ | https://pandoc.org |
| 7-Zip (`7zz`) | 7z and RAR extraction | LGPL 2.1+ with unRAR restriction | https://www.7-zip.org |

## Tools used but not bundled

These are only used if the user has installed them.

| Tool | License | Source |
|---|---|---|
| LibreOffice | MPL 2.0 | https://www.libreoffice.org |
| OCRmyPDF | MPL 2.0 | https://github.com/ocrmypdf/OCRmyPDF |
| pdf2docx | GPL 3 | https://github.com/ArtifexSoftware/pdf2docx |

## Apple system tools

`sips`, `textutil`, `ditto`, and `tar` are provided by macOS and are not redistributed.

## Source availability

For any bundled component licensed under the GPL, LGPL, or AGPL, the corresponding source code is available from the upstream project linked above. If you modified or custom-built any of these tools, publish those sources and build instructions in this repository.
