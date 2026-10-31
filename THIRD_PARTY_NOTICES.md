# Third-Party Notices

DropWheel's own code is released under the MIT License (see `LICENSE`).

The DropWheel app (DMG) **includes** the following programs, unmodified, inside the app at
`DropWheel.app/Contents/Resources/bin` together with the libraries they need in `Contents/Resources/libs`.
DropWheel runs them as separate programs. Each one is owned by its authors and is covered by **its own license**,
which applies to that program only, not to DropWheel's code.

| Program | Used for | Project | License (check the project for current terms) |
|---------|----------|---------|-----------------------------------------------|
| FFmpeg (ffmpeg, ffprobe) | Video and audio | ffmpeg.org | LGPL / GPL, depending on how it is built (the Homebrew build is GPL) |
| Ghostscript (gs) | PDF compress, PDF to text / images | ghostscript.com | AGPL |
| qpdf | PDF merge, split, rotate, unlock | qpdf.sourceforge.io | Apache 2.0 |
| pandoc | Document / Markdown conversion | pandoc.org | GPL |
| 7-Zip (7zz) | Extract 7z / rar archives | 7-zip.org | LGPL, with the unRAR restriction |
| Libraries used by the above (for example x264, x265, lame, libvpx, opus, freetype, lcms2) | Codecs and rendering | their own projects | Various |

## Getting the source code

The GPL and AGPL programs above are redistributed in unmodified form from Homebrew. Their source code is available from
the project websites listed, and from Homebrew (`brew fetch --build-from-source <name>`). You may also ask the
DropWheel maintainer for the exact source versions that were packed into a release.

## Optional programs (NOT included)

- LibreOffice (spreadsheet / slide / Office conversion): libreoffice.org, MPL 2.0
- OCRmyPDF (PDF OCR): github.com/ocrmypdf/OCRmyPDF, MPL 2.0
- pdf2docx (optional): github.com/ArtifexSoftware/pdf2docx

## macOS built-ins

`sips`, `textutil`, `ditto`, `tar` and Apple's frameworks are part of macOS and are not redistributed.

## Disclaimer

DropWheel is provided "as is", without warranty of any kind. Conversions and compression
can change or reduce the quality of your files. Always keep a backup of important files.
The "Unlock" feature is intended only for files you own or are authorized to modify.
