import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ImageIO
import ServiceManagement
import ApplicationServices
import Vision
import PDFKit
import CoreImage
import CryptoKit

// DropWheel — requires macOS 14+, Swift 5 language mode, App Sandbox OFF.
// Single file: this is the ONLY file that should contain @main.

extension Notification.Name {
    static let wheelReset = Notification.Name("dropwheel.reset")
    static let wheelHelp  = Notification.Name("dropwheel.help")
    static let wheelPick  = Notification.Name("dropwheel.pick")
    static let wheelClose = Notification.Name("dropwheel.close")
    static let wheelEsc   = Notification.Name("dropwheel.esc")
    static let wheelPaste = Notification.Name("dropwheel.paste")
}

// MARK: Design tokens

/// Thin specular rim that makes glass surfaces read as physical edges (light from the top-left).
let glassRim = LinearGradient(
    colors: [Color.white.opacity(0.55), Color.white.opacity(0.06), Color.white.opacity(0.22)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

/// Soft sheen across the upper half of a glass surface.
let glassSheen = LinearGradient(
    colors: [Color.white.opacity(0.14), Color.clear, Color.black.opacity(0.05)],
    startPoint: .top, endPoint: .bottom)

extension View {
    /// Floating glass card: material, sheen, specular rim and layered shadows.
    func glassCard(_ radius: CGFloat = 24) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(glassSheen)
                }
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(glassRim, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.30), radius: 30, y: 14)
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

// MARK: - App (menu bar + hotkeys)

@main
struct DropWheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @AppStorage("trashOriginal") private var trashOriginal = false
    @AppStorage("sound") private var sound = true
    @AppStorage("copyResult") private var copyResult = false
    @AppStorage("reveal") private var reveal = true

    var body: some Scene {
        MenuBarExtra("DropWheel", systemImage: "circle.hexagongrid.fill") {
            Button("Show Wheel  (fn or ⌥Space)") { delegate.toggle() }
            Divider()
            Toggle("Launch at login", isOn: $loginOn)
                .onChange(of: loginOn) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { loginOn = SMAppService.mainApp.status == .enabled }
                }
            Toggle("Move original to Trash after converting", isOn: $trashOriginal)
            Toggle("Play sound when done", isOn: $sound)
            Toggle("Copy result to clipboard", isOn: $copyResult)
            Toggle("Reveal result in Finder", isOn: $reveal)
            Divider()
            Button("Save results in…") { delegate.chooseFolder() }
            Button("Save results next to original") { UserDefaults.standard.removeObject(forKey: "outDir") }
            Divider()
            Button("Accessibility permission…") { openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
            Button("Input Monitoring permission…") { openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") }
            Button("Keyboard settings (stop emoji on fn)…") { openSettings("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
            Button("How it works…") { delegate.showHelp() }
            Divider()
            Button("Quit DropWheel") { NSApp.terminate(nil) }
        }
    }
}

func openSettings(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: WheelPanel!
    var fnDown = false
    private var generation = 0          // invalidates a pending fade-out if the wheel is re-opened
    static let panelSize: CGFloat = 520

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let s = AppDelegate.panelSize
        panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: s, height: s),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WheelView())

        // Ask for Accessibility only if it isn't granted AND we haven't asked before.
        // (Granted permission is remembered by macOS, tied to the app's code signature.)
        if !AXIsProcessTrusted() && !UserDefaults.standard.bool(forKey: "askedAX") {
            UserDefaults.standard.set(true, forKey: "askedAX")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        // fn key (global + local)
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e) }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e); return e }

        // Backup hotkey: ⌥Space
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 49 && e.modifierFlags.contains(.option) { self?.toggle() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 {                                   // Esc
                NotificationCenter.default.post(name: .wheelEsc, object: nil); return nil
            }
            if e.keyCode == 49 && e.modifierFlags.contains(.option) { self.toggle(); return nil }
            // Typing in a text field (target size): never treat keys as shortcuts.
            if NSApp.keyWindow?.firstResponder is NSText { return e }
            // ⌘V: load files (or a screenshot) from the clipboard.
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers?.lowercased() == "v" {
                NotificationCenter.default.post(name: .wheelPaste, object: nil); return nil
            }
            let plain = e.modifierFlags.intersection([.command, .option, .control]).isEmpty
            if plain, let c = e.charactersIgnoringModifiers?.lowercased() {
                if c == "h" || c == "/" {
                    NotificationCenter.default.post(name: .wheelHelp, object: nil); return nil
                }
                if let n = Int(c), (0...9).contains(n) {
                    NotificationCenter.default.post(name: .wheelPick, object: n == 0 ? 10 : n); return nil
                }
            }
            return e
        }
        NotificationCenter.default.addObserver(forName: .wheelClose, object: nil, queue: .main) { [weak self] _ in
            self?.hide()
        }
    }

    func flags(_ e: NSEvent) {
        let down = e.modifierFlags.contains(.function)
        if down && !fnDown { toggle() }
        fnDown = down
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        generation += 1
        let wasVisible = panel.isVisible
        NotificationCenter.default.post(name: .wheelReset, object: nil)
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.frame {
            let h = AppDelegate.panelSize / 2
            panel.setFrameOrigin(NSPoint(x: f.midX - h, y: f.midY - h))
        }
        if !wasVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        generation += 1
        let g = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, g == self.generation else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let op = NSOpenPanel()
        op.canChooseFiles = false; op.canChooseDirectories = true; op.canCreateDirectories = true
        op.prompt = "Save here"
        if op.runModal() == .OK, let u = op.url { UserDefaults.standard.set(u.path, forKey: "outDir") }
    }

    func showHelp() {
        show()
        NotificationCenter.default.post(name: .wheelHelp, object: nil)
    }
}

// MARK: - Actions

enum FileKind { case image, video, audio, pdf, document, markdown, sheet, slides, archive, data, other }

struct WheelAction: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let tool: String
    let brew: String
    let ext: String?
    let suffix: String
    let temp: Bool
    let compress: Bool
    let sizing: Bool        // opens the "target size" card instead of running directly
    let renaming: Bool      // opens the rename card
    let native: ((_ input: String, _ output: URL, _ job: Job) -> String?)?   // per-file, runs inside the app; returns an error or nil
    let batch: ((_ files: [URL], _ job: Job) -> BatchResult)?                // works on the whole selection, any mix of types
    let args: (_ input: String, _ output: String) -> [String]
}

struct BatchResult {
    var note = ""
    var outs: [URL] = []
    var error: String? = nil
}

func act(_ title: String, _ icon: String, _ tool: String, brew: String = "", ext: String?,
         suffix: String = "", temp: Bool = false, compress: Bool = false, sizing: Bool = false,
         renaming: Bool = false,
         args: @escaping (String, String) -> [String],
         native: ((String, URL, Job) -> String?)? = nil,
         batch: ((_ files: [URL], _ job: Job) -> BatchResult)? = nil) -> WheelAction {
    WheelAction(title: title, icon: icon, tool: tool, brew: brew, ext: ext, suffix: suffix,
                temp: temp, compress: compress, sizing: sizing, renaming: renaming,
                native: native, batch: batch, args: args)
}

/// An action implemented inside the app (no external tool).
func nat(_ title: String, _ icon: String, ext: String?, suffix: String = "",
         _ f: @escaping (String, URL, Job) -> String?) -> WheelAction {
    act(title, icon, "native", ext: ext, suffix: suffix, args: { _, _ in [] }, native: f)
}

/// An action that works on the whole selection at once (any mix of file types).
func bat(_ title: String, _ icon: String, _ f: @escaping ([URL], Job) -> BatchResult) -> WheelAction {
    act(title, icon, "batch", ext: nil, args: { _, _ in [] }, batch: f)
}

let moreID = "More ›"

let soffice = "/Applications/LibreOffice.app/Contents/MacOS/soffice"

/// LibreOffice args with a private profile so it works even if LibreOffice is already open.
func loArgs(_ i: String, _ o: String, _ convertArgs: [String]) -> [String] {
    let profile = URL(fileURLWithPath: o).deletingLastPathComponent()
        .appendingPathComponent("lo-profile").absoluteString
    return ["-env:UserInstallation=" + profile, "--headless"] + convertArgs + ["--outdir", o, i]
}

func gs(_ title: String, _ icon: String, _ preset: String) -> WheelAction {
    act(title, icon, "gs", brew: "ghostscript", ext: "pdf", suffix: "-small", compress: true) { i, o in
        ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=\(preset)", "-dDetectDuplicateImages=true",
         "-dNOPAUSE", "-dBATCH", "-dQUIET", "-sOutputFile=\(o)", i]
    }
}

func toPDF() -> WheelAction {
    act("To PDF", "doc.richtext", soffice, brew: "--cask libreoffice", ext: "pdf", temp: true) { i, o in
        loArgs(i, o, ["--convert-to", "pdf"])
    }
}

func textutil(_ title: String, _ icon: String, _ f: String) -> WheelAction {
    act(title, icon, "textutil", ext: f) { i, o in ["-convert", f, i, "-output", o] }
}

func sips(_ title: String, _ icon: String, _ f: String, ext: String) -> WheelAction {
    act(title, icon, "sips", ext: ext) { i, o in ["-s", "format", f, i, "--out", o] }
}

func ff(_ t: String, _ icon: String, _ ext: String?, suffix: String = "", compress: Bool = false,
        _ a: @escaping (String, String) -> [String]) -> WheelAction {
    act(t, icon, "ffmpeg", brew: "ffmpeg", ext: ext, suffix: suffix, compress: compress, args: a)
}
func lo(_ t: String, _ icon: String, _ f: String) -> WheelAction {
    act(t, icon, soffice, brew: "--cask libreoffice", ext: f, temp: true) { i, o in
        loArgs(i, o, ["--convert-to", f]) }
}
func pd(_ t: String, _ icon: String, _ ext: String) -> WheelAction {
    act(t, icon, "pandoc", brew: "pandoc", ext: ext) { i, o in ["-s", i, "-o", o] }
}
func targetSize() -> WheelAction {
    act("Set Size", "scalemass", "-", ext: nil, compress: true, sizing: true) { _, _ in [] }
}

func actions(for url: URL) -> [WheelAction] {
    var e = url.pathExtension.lowercased()
    e = ["jpeg": "jpg", "tif": "tiff", "htm": "html", "heif": "heic", "markdown": "md", "aif": "aiff"][e] ?? e
    let h264 = ["-vcodec", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-acodec", "aac"]
    let small = ["-vcodec", "libx264", "-crf", "26", "-preset", "fast", "-pix_fmt", "yuv420p", "-acodec", "aac", "-b:a", "128k"]
    let checksum = nat("Checksum", "number.circle", ext: "txt", suffix: "-checksum", nativeHash)

    let list: [WheelAction]
    switch kind(of: url) {
    case .image:
        list = [
            targetSize(),
            sips("To JPG", "photo", "jpeg", ext: "jpg"),
            sips("To PNG", "photo.fill", "png", ext: "png"),
            sips("To HEIC", "photo.stack", "heic", ext: "heic"),
            ff("To WebP", "globe", "webp") { i, o in ["-y", "-i", i, "-q:v", "85", o] },
            sips("To PDF", "doc.richtext", "pdf", ext: "pdf"),
            sips("To TIFF", "photo.on.rectangle", "tiff", ext: "tiff"),
            nat("Copy Text", "text.viewfinder", ext: "txt", suffix: "-text", nativeOCR),
            nat("No Background", "person.crop.rectangle", ext: "png", suffix: "-nobg", nativeRemoveBG),
            act("Rotate", "rotate.right", "sips", ext: nil, suffix: "-rotated") { i, o in ["-r", "90", i, "--out", o] },
            act("Shrink", "arrow.down.right.and.arrow.up.left", "sips", ext: "jpg", suffix: "-small", compress: true) { i, o in
                ["-s", "format", "jpeg", "-s", "formatOptions", "70", "--resampleHeightWidthMax", "2400", i, "--out", o] },
            act("Resize", "arrow.up.left.and.arrow.down.right", "sips", ext: nil, suffix: "-1080", compress: true) { i, o in
                ["--resampleHeightWidthMax", "1080", i, "--out", o] }
        ]
    case .video:
        list = [
            targetSize(),
            ff("Compress", "arrow.down.right.and.arrow.up.left", "mp4", suffix: "-small", compress: true) { i, o in ["-y", "-i", i] + small + [o] },
            ff("720p", "rectangle.compress.vertical", "mp4", suffix: "-720p", compress: true) { i, o in ["-y", "-i", i, "-vf", "scale=-2:720"] + small + [o] },
            ff("H.265", "bolt.horizontal", "mp4", suffix: "-hevc", compress: true) { i, o in
                ["-y", "-i", i, "-vcodec", "libx265", "-crf", "28", "-preset", "fast", "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-acodec", "aac", "-b:a", "128k", o] },
            ff("To MP4", "film", "mp4") { i, o in ["-y", "-i", i] + h264 + [o] },
            ff("To MOV", "film.stack", "mov") { i, o in ["-y", "-i", i] + h264 + [o] },
            ff("To MKV", "square.stack.3d.down.right", "mkv") { i, o in ["-y", "-i", i, "-c", "copy", o] },
            ff("To WebM", "globe", "webm") { i, o in ["-y", "-i", i, "-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", o] },
            ff("To GIF", "sparkles.tv", "gif") { i, o in ["-y", "-i", i, "-vf", "fps=12,scale=480:-1", o] },
            ff("To MP3", "music.note", "mp3") { i, o in ["-y", "-i", i, "-vn", "-q:a", "2", o] },
            ff("Mute", "speaker.slash", nil, suffix: "-mute") { i, o in ["-y", "-i", i, "-c", "copy", "-an", o] },
            ff("Frame→PNG", "photo", "png") { i, o in ["-y", "-i", i, "-frames:v", "1", o] }
        ]
    case .audio:
        list = [
            targetSize(),
            ff("To MP3", "music.note", "mp3") { i, o in ["-y", "-i", i, "-vn", "-b:a", "192k", o] },
            ff("To M4A", "music.note.list", "m4a") { i, o in ["-y", "-i", i, "-vn", "-c:a", "aac", "-b:a", "192k", o] },
            ff("To WAV", "waveform", "wav") { i, o in ["-y", "-i", i, "-vn", o] },
            ff("To FLAC", "waveform.badge.plus", "flac") { i, o in ["-y", "-i", i, "-vn", o] },
            ff("To OGG", "dot.radiowaves.left.and.right", "ogg") { i, o in ["-y", "-i", i, "-vn", "-c:a", "libvorbis", "-q:a", "5", o] },
            ff("To OPUS", "antenna.radiowaves.left.and.right", "opus") { i, o in ["-y", "-i", i, "-vn", "-c:a", "libopus", "-b:a", "128k", o] },
            ff("To AIFF", "waveform.path", "aiff") { i, o in ["-y", "-i", i, "-vn", o] },
            ff("Normalize", "slider.horizontal.3", nil, suffix: "-norm") { i, o in ["-y", "-i", i, "-vn", "-af", "loudnorm", o] },
            ff("Compress", "arrow.down.right.and.arrow.up.left", "mp3", suffix: "-small", compress: true) { i, o in ["-y", "-i", i, "-vn", "-b:a", "96k", o] }
        ]
    case .pdf:
        let toDocx: WheelAction = locate("pdf2docx") != nil
            ? act("To DOCX", "doc.fill", "pdf2docx", brew: "pipx install pdf2docx", ext: "docx") { i, o in ["convert", i, o] }
            : act("To DOCX", "doc.fill", soffice, brew: "--cask libreoffice", ext: "docx", temp: true) { i, o in
                loArgs(i, o, ["--infilter=writer_pdf_import", "--convert-to", "docx"]) }
        let gsBin = locate("gs") ?? "gs"
        let qpdfBin = locate("qpdf") ?? "qpdf"
        list = [
            targetSize(),
            act("Lossless", "checkmark.seal", "qpdf", brew: "qpdf", ext: "pdf", suffix: "-lossless", compress: true) { i, o in
                ["--object-streams=generate", "--recompress-flate", "--compression-level=9", i, o] },
            gs("Smart", "wand.and.stars", "/prepress"),
            gs("Strong", "arrow.down.right.and.arrow.up.left", "/ebook"),
            toDocx,
            act("To TXT", "text.alignleft", "gs", brew: "ghostscript", ext: "txt") { i, o in
                ["-sDEVICE=txtwrite", "-dNOPAUSE", "-dBATCH", "-dQUIET", "-sOutputFile=\(o)", i] },
            act("Split", "rectangle.split.3x1", "sh", brew: "qpdf", ext: "", suffix: "-pages") { i, o in
                ["-c", "mkdir -p \"$2\" && \(qpdfBin) --split-pages \"$1\" \"$2/page.pdf\"", "_", i, o] },
            // Every page as a numbered JPG in a new folder (good for sharing / slides / scans).
            act("All Pages", "photo.on.rectangle.angled", "sh", brew: "ghostscript", ext: "", suffix: "-images") { i, o in
                ["-c", "mkdir -p \"$2\" && \(gsBin) -sDEVICE=jpeg -dJPEGQ=90 -r150 -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dNOPAUSE -dBATCH -dQUIET -sOutputFile=\"$2/page-%03d.jpg\" \"$1\"", "_", i, o] },
            // Removes owner-password restrictions (no copy / no print / no edit).
            act("Unlock", "lock.open", "qpdf", brew: "qpdf", ext: "pdf", suffix: "-unlocked") { i, o in
                ["--decrypt", i, o] },
            // Black & white version: cheaper to print, often smaller.
            act("Grayscale", "circle.lefthalf.filled", "gs", brew: "ghostscript", ext: "pdf", suffix: "-gray") { i, o in
                ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-sColorConversionStrategy=Gray", "-dProcessColorModel=/DeviceGray",
                 "-dNOPAUSE", "-dBATCH", "-dQUIET", "-sOutputFile=\(o)", i] },
            act("Rotate", "rotate.right", "qpdf", brew: "qpdf", ext: "pdf", suffix: "-rotated") { i, o in ["--rotate=+90", i, o] },
            act("OCR", "text.viewfinder", "ocrmypdf", brew: "ocrmypdf", ext: "pdf", suffix: "-ocr") { i, o in ["--skip-text", "--optimize", "0", i, o] }
        ]
    case .document:
        list = [
            textutil("To DOCX", "doc.fill", "docx"),
            textutil("To DOC", "doc", "doc"),
            toPDF(),
            textutil("To TXT", "text.alignleft", "txt"),
            textutil("To RTF", "textformat", "rtf"),
            textutil("To HTML", "chevron.left.forwardslash.chevron.right", "html"),
            textutil("To ODT", "doc.text", "odt"),
            pd("To MD", "number", "md"),
            pd("To EPUB", "book", "epub")
        ]
    case .markdown:
        list = [
            pd("To DOCX", "doc.fill", "docx"), pd("To ODT", "doc.text", "odt"),
            pd("To HTML", "chevron.left.forwardslash.chevron.right", "html"),
            pd("To EPUB", "book", "epub"), pd("To RTF", "textformat", "rtf"), pd("To TXT", "text.alignleft", "txt")
        ]
    case .sheet:
        list = [lo("To PDF", "doc.richtext", "pdf"), lo("To XLSX", "tablecells", "xlsx"), lo("To CSV", "list.bullet.rectangle", "csv"),
                lo("To ODS", "tablecells.fill", "ods"),
                lo("To HTML", "chevron.left.forwardslash.chevron.right", "html")]
    case .slides:
        list = [lo("To PDF", "doc.richtext", "pdf"), lo("To PPTX", "rectangle.on.rectangle", "pptx"),
                lo("To ODP", "rectangle.on.rectangle.angled", "odp"), lo("Slide 1→PNG", "photo", "png")]
    case .archive:
        if e == "zip" {
            list = [act("Extract", "archivebox", "ditto", ext: "") { i, o in ["-x", "-k", i, o] }, checksum]
        } else if e == "7z" || e == "rar" {
            list = [act("Extract", "archivebox", "7zz", brew: "sevenzip", ext: "") { i, o in ["x", i, "-o" + o, "-y"] }, checksum]
        } else {
            list = [act("Extract", "archivebox", "sh", ext: "") { i, o in ["-c", "mkdir -p \"$2\" && tar -xf \"$1\" -C \"$2\"", "_", i, o] }, checksum]
        }
    case .data:
        list = [
            act("Pretty", "text.alignleft", "sh", ext: nil, suffix: "-pretty") { i, o in ["-c", "python3 -m json.tool \"$1\" > \"$2\"", "_", i, o] },
            act("Minify", "arrow.down.right.and.arrow.up.left", "sh", ext: nil, suffix: "-min") { i, o in
                ["-c", "python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(\",\", \":\")))' \"$1\" > \"$2\"", "_", i, o] },
            checksum
        ]
    case .other:
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        list = isDir ? [] : [checksum]
    }
    return list.filter { !($0.suffix.isEmpty && $0.ext == e) }
}

func kind(of url: URL) -> FileKind {
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { return .other }
    let e = url.pathExtension.lowercased()
    if ["doc", "docx", "rtf", "rtfd", "txt", "html", "htm", "odt"].contains(e) { return .document }
    if ["md", "markdown"].contains(e) { return .markdown }
    if e == "json" { return .data }
    if ["xls", "xlsx", "ods", "csv", "tsv"].contains(e) { return .sheet }
    if ["ppt", "pptx", "odp"].contains(e) { return .slides }
    if ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"].contains(e) { return .archive }
    if ["mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp"].contains(e) { return .video }
    if ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aac", "aiff", "aif", "wma", "caf"].contains(e) { return .audio }
    if ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "jp2", "ico", "psd"].contains(e) { return .image }
    if e == "pdf" { return .pdf }
    guard let t = UTType(filenameExtension: e) else { return .other }
    if t.conforms(to: .image) { return .image }
    if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
    if t.conforms(to: .audio) { return .audio }
    if t.conforms(to: .pdf) { return .pdf }
    return .other
}

func wheelList(_ files: [URL]) -> [WheelAction] {
    var l = actions(for: files[0])
    if files.count > 1 && files.allSatisfy({ kind(of: $0) == .pdf }) {
        l.insert(act("Merge", "square.on.square", "qpdf", brew: "qpdf", ext: "pdf", suffix: "-merged") { i, o in
            ["--empty", "--pages"] + i.components(separatedBy: "\u{1}") + ["--", o] }, at: 0)
    }
    if files.count > 1 && files.allSatisfy({ kind(of: $0) == .image }) {
        l.insert(nat("Combine to PDF", "doc.on.doc", ext: "pdf", suffix: "-combined", nativeImagesToPDF), at: 0)
    }
    return l + universalActions(files)
}

/// Formats ExifTool can strip metadata from reliably.
let cleanableExts: Set<String> = ["jpg", "png", "webp", "tiff", "gif", "heic", "mp4", "mov", "m4v", "m4a",
                                  "mp3", "flac", "wav", "docx", "xlsx", "pptx", "odt", "ods", "odp"]

/// Tools that work on ANY file type (always the last wedges of the wheel).
func universalActions(_ files: [URL]) -> [WheelAction] {
    func norm(_ u: URL) -> String {
        let e = u.pathExtension.lowercased()
        return ["jpeg": "jpg", "tif": "tiff", "heif": "heic"][e] ?? e
    }
    var u: [WheelAction] = []
    if files.allSatisfy({ cleanableExts.contains(norm($0)) }) {
        // Removes location, camera, author, dates… Great before sharing a file publicly.
        u.append(act("Clean Info", "location.slash", "exiftool", brew: "exiftool", ext: nil, suffix: "-clean") { i, o in
            ["-all=", "-o", o, i] })
    }
    u.append(act("Rename", "pencil", "-", ext: nil, renaming: true, args: { _, _ in [] }))
    u.append(bat(files.count > 1 ? "Zip All" : "Zip", "doc.zipper") { f, j in zipFiles(f, job: j) })
    let single = files.count == 1
    let isDir = single && ((try? files[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true)
    if !single || isDir {
        u.append(bat("Sort Type", "folder") { f, j in sortFiles(f, byDate: false, job: j) })
        u.append(bat("Sort Date", "calendar") { f, j in sortFiles(f, byDate: true, job: j) })
    }
    u.append(bat("AirDrop", "square.and.arrow.up") { f, _ in
        shareBatch(.sendViaAirDrop, name: "AirDrop", note: "Pick a device", f) })
    u.append(bat("Mail", "envelope") { f, _ in
        shareBatch(.composeEmail, name: "Mail", note: "Opening Mail", f) })
    u.append(bat("Copy", "doc.on.clipboard") { f, _ in copyFiles(f) })
    return u
}

// MARK: - Helpers

func playSound(_ name: String) {
    if UserDefaults.standard.object(forKey: "sound") as? Bool ?? true { NSSound(named: name)?.play() }
}

func locate(_ tool: String) -> String? {
    let fm = FileManager.default
    if tool.hasPrefix("/") { return fm.isExecutableFile(atPath: tool) ? tool : nil }
    for dir in ["/usr/bin/", "/bin/", "/opt/homebrew/bin/", "/usr/local/bin/", NSHomeDirectory() + "/.local/bin/"] {
        if fm.isExecutableFile(atPath: dir + tool) { return dir + tool }
    }
    return nil
}

func uniqueOutput(for input: URL, suffix: String, ext: String?) -> URL {
    var dir = input.deletingLastPathComponent()
    if let p = UserDefaults.standard.string(forKey: "outDir") {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
            dir = URL(fileURLWithPath: p)
        }
    }
    let base = input.deletingPathExtension().lastPathComponent + suffix
    let e = ext ?? input.pathExtension
    func make(_ name: String) -> URL {
        let u = dir.appendingPathComponent(name)
        return e.isEmpty ? u : u.appendingPathExtension(e)
    }
    var out = make(base)
    var n = 2
    while FileManager.default.fileExists(atPath: out.path) {
        out = make("\(base) \(n)")
        n += 1
    }
    return out
}

func fileSize(_ u: URL) -> Int64 {
    let a = try? FileManager.default.attributesOfItem(atPath: u.path)
    return (a?[.size] as? NSNumber)?.int64Value ?? 0
}
func human(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

func makeTemp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("dw-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func lastLine(_ s: String) -> String {
    let l = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? "Conversion failed"
    return String(l.suffix(90))
}

func copyText(_ s: String) {
    DispatchQueue.main.async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Files copied in Finder, or an image on the clipboard (saved to Downloads as Clipboard.png).
func pasteboardFiles() -> [URL] {
    let pb = NSPasteboard.general
    if let urls = pb.readObjects(forClasses: [NSURL.self],
                                 options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
        return urls
    }
    if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let fm = FileManager.default
        let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        var f = dir.appendingPathComponent("Clipboard.png")
        var n = 2
        while fm.fileExists(atPath: f.path) {
            f = dir.appendingPathComponent("Clipboard \(n).png")
            n += 1
        }
        do { try png.write(to: f); return [f] } catch { return [] }
    }
    return []
}

// MARK: - Wedge shape

/// A ring segment with rounded corners and a constant-width gap to its neighbours.
/// Built by shrinking the segment and stroking it with a round line join (stroke width = 2 × `round`),
/// so the final silhouette is the shrunken shape expanded by `round`.
struct Wedge: Shape {
    var start: Angle, end: Angle
    var inner: CGFloat, outer: CGFloat
    var gap: CGFloat = 3
    var round: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let ro = outer - round
        let ri = inner + round
        let d = gap / 2 + round                          // distance of each side edge from the radial line
        let ao = asin(min(d / ro, 1))
        let ai = asin(min(d / ri, 1))
        let s = start.radians, e = end.radians
        var p = Path()
        p.addArc(center: c, radius: ro, startAngle: .radians(s + ao), endAngle: .radians(e - ao), clockwise: false)
        p.addArc(center: c, radius: ri, startAngle: .radians(e - ai), endAngle: .radians(s + ai), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Process running

/// Thread-safe handle so a running job can be cancelled from the UI.
final class Job: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var proc: Process?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func set(_ p: Process?) { lock.lock(); proc = p; lock.unlock() }
    func cancel() {
        lock.lock(); _cancelled = true; let p = proc; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
}

struct Outcome {
    var url: URL?
    var error = ""
    var before: Int64 = 0
    var after: Int64 = 0
    var reached = true       // false when a target size could not be met
}
final class URLBox { var urls: [URL] = [] }

@discardableResult
func runTool(_ path: String, _ args: [String], job: Job) -> (status: Int32, out: String, err: String) {
    if job.cancelled { return (-1, "", "Cancelled") }
    let fm = FileManager.default
    let tmp = makeTemp()
    defer { try? fm.removeItem(at: tmp) }
    let outURL = tmp.appendingPathComponent("o.txt"), errURL = tmp.appendingPathComponent("e.txt")
    fm.createFile(atPath: outURL.path, contents: nil)
    fm.createFile(atPath: errURL.path, contents: nil)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    p.environment = env
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = (try? FileHandle(forWritingTo: outURL)) ?? FileHandle.nullDevice
    p.standardError = (try? FileHandle(forWritingTo: errURL)) ?? FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "", error.localizedDescription) }
    job.set(p)
    if job.cancelled { p.terminate() }
    p.waitUntilExit()
    job.set(nil)
    let o = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
    let e = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
    return (p.terminationStatus, o, e)
}

// MARK: - Native actions (no external tools)

func loadCG(_ url: URL, maxSize: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int,
          let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
    let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceCreateThumbnailWithTransform: true,
                              kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), maxSize),
                              kCGImageSourceShouldCacheImmediately: true]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
}

/// Text recognition (OCR) with Apple Vision. Saves a .txt and copies the text to the clipboard.
func nativeOCR(_ path: String, _ out: URL, _ job: Job) -> String? {
    func read(_ cg: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req]) } catch { return "" }
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
    let url = URL(fileURLWithPath: path)
    var text = ""
    if url.pathExtension.lowercased() == "pdf" {
        guard let doc = PDFDocument(url: url) else { return "Can't open PDF" }
        for i in 0..<doc.pageCount {
            if job.cancelled { return "Cancelled" }
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let img = page.thumbnail(of: CGSize(width: b.width * 2, height: b.height * 2), for: .mediaBox)
            if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                text += (text.isEmpty ? "" : "\n\n") + read(cg)
            }
        }
    } else {
        guard let cg = loadCG(url, maxSize: 5000) else { return "Can't read this image" }
        text = read(cg)
    }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No text found" }
    do { try text.write(to: out, atomically: true, encoding: .utf8) } catch { return "Couldn't save text" }
    copyText(text)
    return nil
}

/// Cuts out the main subject (macOS 14+). Saves a transparent PNG.
func nativeRemoveBG(_ path: String, _ out: URL, _ job: Job) -> String? {
    guard let cg = loadCG(URL(fileURLWithPath: path), maxSize: 4096) else { return "Can't read this image" }
    let req = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([req]) } catch { return "Couldn't analyse image" }
    guard let res = req.results?.first else { return "No subject found" }
    guard let buf = try? res.generateMaskedImage(ofInstances: res.allInstances, from: handler,
                                                  croppedToInstancesExtent: false) else { return "Couldn't cut out subject" }
    let ctx = CIContext()
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let png = ctx.pngRepresentation(of: CIImage(cvPixelBuffer: buf), format: .RGBA8, colorSpace: space)
    else { return "Couldn't encode PNG" }
    do { try png.write(to: out) } catch { return "Couldn't save image" }
    return nil
}

/// Several images → one PDF (the input is the paths joined with \u{1}).
func nativeImagesToPDF(_ joined: String, _ out: URL, _ job: Job) -> String? {
    let doc = PDFDocument()
    for p in joined.components(separatedBy: "\u{1}") {
        if job.cancelled { return "Cancelled" }
        if let img = NSImage(contentsOf: URL(fileURLWithPath: p)), let page = PDFPage(image: img) {
            doc.insert(page, at: doc.pageCount)
        }
    }
    return (doc.pageCount > 0 && doc.write(to: out)) ? nil : "Couldn't build the PDF"
}

/// SHA-256 → saved next to the file and copied to the clipboard.
func nativeHash(_ path: String, _ out: URL, _ job: Job) -> String? {
    guard let fh = FileHandle(forReadingAtPath: path) else { return "Can't read file" }
    defer { try? fh.close() }
    var h = SHA256()
    while true {
        if job.cancelled { return "Cancelled" }
        guard let d = try? fh.read(upToCount: 4_000_000), !d.isEmpty else { break }
        h.update(data: d)
    }
    let hex = h.finalize().map { String(format: "%02x", $0) }.joined()
    let line = hex + "  " + (path as NSString).lastPathComponent + "\n"
    do { try line.write(to: out, atomically: true, encoding: .utf8) } catch { return "Couldn't save checksum" }
    copyText(hex)
    return nil
}

// MARK: - Batch tools (any file type)

func isDirectory(_ u: URL) -> Bool {
    (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
}

/// Builds a new file name from a pattern. Tokens: {name} original name, {n} counter, {date} file date.
func renamedName(_ url: URL, index: Int, total: Int, pattern: String, start: Int, slug: Bool) -> String {
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    let num = String(start + index)
    let width = String(start + max(total, 1) - 1).count
    let padded = String(repeating: "0", count: max(0, width - num.count)) + num
    let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd"
    var s = pattern
        .replacingOccurrences(of: "{name}", with: base)
        .replacingOccurrences(of: "{n}", with: padded)
        .replacingOccurrences(of: "{date}", with: df.string(from: created))
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
    if slug {
        let mapped = s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == "_") ? String($0) : "-" }.joined()
        s = mapped.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    s = s.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { s = base }
    return ext.isEmpty ? s : s + "." + ext
}

/// Renames files in place (two-phase, so swaps and case-only changes are safe; rolls back on failure).
func renameFiles(_ files: [URL], pattern: String, start: Int, slug: Bool, job: Job) -> BatchResult {
    let fm = FileManager.default
    let sources = Set(files.map { $0.path.lowercased() })
    var claimed = Set<String>()

    func taken(_ u: URL) -> Bool {
        let key = u.path.lowercased()
        if claimed.contains(key) { return true }
        return fm.fileExists(atPath: u.path) && !sources.contains(key)
    }

    var plan: [(src: URL, dst: URL)] = []
    for (i, f) in files.enumerated() {
        let dir = f.deletingLastPathComponent()
        let name = renamedName(f, index: i, total: files.count, pattern: pattern, start: start, slug: slug)
        var dst = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while taken(dst) {
            dst = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        claimed.insert(dst.path.lowercased())
        plan.append((f, dst))
    }

    var staged: [(tmp: URL, src: URL, dst: URL)] = []
    func rollback() { for s in staged.reversed() { try? fm.moveItem(at: s.tmp, to: s.src) } }

    for p in plan where p.src.path != p.dst.path {
        if job.cancelled { rollback(); return BatchResult(error: "Cancelled") }
        let tmp = p.src.deletingLastPathComponent().appendingPathComponent(".dw-" + UUID().uuidString)
        do {
            try fm.moveItem(at: p.src, to: tmp)
            staged.append((tmp, p.src, p.dst))
        } catch {
            rollback()
            return BatchResult(error: "Couldn’t rename \(p.src.lastPathComponent)")
        }
    }
    if staged.isEmpty { return BatchResult(error: "Names are already like that") }

    var done: [URL] = []
    var failed = 0
    for s in staged {
        do { try fm.moveItem(at: s.tmp, to: s.dst); done.append(s.dst) }
        catch { try? fm.moveItem(at: s.tmp, to: s.src); failed += 1 }
    }
    if done.isEmpty { return BatchResult(error: "Couldn’t rename") }
    var note = done.count == 1 ? "Renamed" : "\(done.count) files renamed"
    if failed > 0 { note += "\n\(failed) failed" }
    return BatchResult(note: note, outs: done, error: nil)
}

/// One archive with everything in it (a single file or folder is zipped directly).
func zipFiles(_ files: [URL], job: Job) -> BatchResult {
    guard let first = files.first else { return BatchResult(error: "Nothing to zip") }
    let fm = FileManager.default
    let tmp = makeTemp()
    defer { try? fm.removeItem(at: tmp) }
    let out: URL
    var source = first
    if files.count == 1 {
        out = uniqueOutput(for: first, suffix: "", ext: "zip")
    } else {
        let stage = tmp.appendingPathComponent("Archive", isDirectory: true)
        do { try fm.createDirectory(at: stage, withIntermediateDirectories: true) }
        catch { return BatchResult(error: "Couldn’t prepare files") }
        for f in files {
            if job.cancelled { return BatchResult(error: "Cancelled") }
            var dest = stage.appendingPathComponent(f.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = f.deletingPathExtension().lastPathComponent
                let e = f.pathExtension
                dest = stage.appendingPathComponent(e.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(e)")
                n += 1
            }
            do { try fm.copyItem(at: f, to: dest) }
            catch { return BatchResult(error: "Couldn’t read \(f.lastPathComponent)") }
        }
        source = stage
        out = uniqueOutput(for: first.deletingLastPathComponent().appendingPathComponent("Archive"), suffix: "", ext: "zip")
    }
    let r = runTool("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, out.path], job: job)
    guard r.status == 0, fm.fileExists(atPath: out.path) else {
        try? fm.removeItem(at: out)
        return BatchResult(error: job.cancelled ? "Cancelled" : lastLine(r.err))
    }
    return BatchResult(note: human(fileSize(out)), outs: [out], error: nil)
}

func sortFolderName(_ u: URL) -> String {
    switch kind(of: u) {
    case .image: return "Images"
    case .video: return "Videos"
    case .audio: return "Audio"
    case .pdf: return "PDFs"
    case .document, .markdown: return "Documents"
    case .sheet: return "Spreadsheets"
    case .slides: return "Presentations"
    case .archive: return "Archives"
    case .data: return "Data"
    case .other: return "Other"
    }
}

/// Tidies files into sub-folders by type or by month. A single dropped folder sorts its contents.
func sortFiles(_ input: [URL], byDate: Bool, job: Job) -> BatchResult {
    let fm = FileManager.default
    var files = input
    if input.count == 1, isDirectory(input[0]) {
        files = (try? fm.contentsOfDirectory(at: input[0], includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles])) ?? []
    }
    files = files.filter { !isDirectory($0) }
    if files.isEmpty { return BatchResult(error: "Nothing to sort") }

    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM"
    var folders: [String: URL] = [:]
    var moved = 0

    for f in files {
        if job.cancelled { break }
        let created = (try? f.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        let name = byDate ? df.string(from: created) : sortFolderName(f)
        let parent = f.deletingLastPathComponent()
        if parent.lastPathComponent == name { continue }          // already sorted
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var dest = dir.appendingPathComponent(f.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = f.deletingPathExtension().lastPathComponent
                let e = f.pathExtension
                dest = dir.appendingPathComponent(e.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(e)")
                n += 1
            }
            try fm.moveItem(at: f, to: dest)
            moved += 1
            folders[dir.path] = dir
        } catch { continue }
    }
    if job.cancelled { return BatchResult(error: "Cancelled") }
    if moved == 0 { return BatchResult(error: "Nothing to move") }
    return BatchResult(note: "\(moved) files → \(folders.count) folders", outs: Array(folders.values), error: nil)
}

/// Opens the system share service (AirDrop / Mail) with the files.
func shareBatch(_ service: NSSharingService.Name, name: String, note: String, _ files: [URL]) -> BatchResult {
    var ok = false
    DispatchQueue.main.sync {
        if let s = NSSharingService(named: service), s.canPerform(withItems: files) {
            s.perform(withItems: files)
            ok = true
        }
    }
    return ok ? BatchResult(note: note, outs: [], error: nil)
              : BatchResult(error: "\(name) isn’t available")
}

/// Puts the files themselves on the clipboard so they can be pasted into Finder, Slack, Mail…
func copyFiles(_ files: [URL]) -> BatchResult {
    DispatchQueue.main.sync {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(files as [NSURL])
    }
    return BatchResult(note: files.count > 1 ? "\(files.count) files copied" : "Copied", outs: [], error: nil)
}

// MARK: - Normal conversion

func convert(_ action: WheelAction, tool: String, input: URL, inputPath: String? = nil, job: Job) -> Outcome {
    let fm = FileManager.default
    let output = uniqueOutput(for: input, suffix: action.suffix, ext: action.ext)
    let tmp = makeTemp()
    let work = tmp.appendingPathComponent("out")
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    // Actions implemented inside the app.
    if let run = action.native {
        if let err = run(inputPath ?? input.path, output, job) {
            try? fm.removeItem(at: output)
            return Outcome(error: job.cancelled ? "Cancelled" : err)
        }
        guard fm.fileExists(atPath: output.path) else { return Outcome(error: "Nothing was produced") }
        return Outcome(url: output, before: fileSize(input), after: fileSize(output))
    }

    let r = runTool(tool, action.args(inputPath ?? input.path, action.temp ? work.path : output.path), job: job)
    var ok = r.status == 0 || (action.tool == "qpdf" && r.status == 3)

    if ok && action.temp {
        if let f = (try? fm.contentsOfDirectory(atPath: work.path))?.first(where: { !$0.hasPrefix(".") }) {
            do { try fm.moveItem(at: work.appendingPathComponent(f), to: output) } catch { ok = false }
        } else { ok = false }
    }
    if !ok || !fm.fileExists(atPath: output.path) {
        try? fm.removeItem(at: output)
        if job.cancelled { return Outcome(error: "Cancelled") }
        if (r.err.contains("command not found") || r.err.contains("No such file")) && !action.brew.isEmpty {
            return Outcome(error: "Missing tool. In Terminal run: brew install \(action.brew)")
        }
        return Outcome(error: lastLine(r.err))
    }
    var o = Outcome(url: output, before: fileSize(input), after: fileSize(output))
    if action.compress && o.after >= o.before {          // no gain: keep the original untouched
        try? fm.removeItem(at: output); o.url = input; o.after = o.before
    }
    return o
}

// MARK: - Target-size compression

/// Moves a finished temp file next to the original (or into the chosen folder).
func commit(_ tmpFile: URL, input: URL, ext: String, before: Int64, reached: Bool) -> Outcome {
    let after = fileSize(tmpFile)
    if after >= before { return Outcome(url: input, before: before, after: before, reached: false) }
    let out = uniqueOutput(for: input, suffix: "-compressed", ext: ext)
    do { try FileManager.default.moveItem(at: tmpFile, to: out) }
    catch { return Outcome(error: "Couldn't save the result") }
    return Outcome(url: out, before: before, after: after, reached: reached)
}

func compressToTarget(_ input: URL, target: Int64, job: Job) -> Outcome {
    let before = fileSize(input)
    if before <= target { return Outcome(url: input, before: before, after: before) }
    switch kind(of: input) {
    case .image: return shrinkImage(input, target: target, before: before, job: job)
    case .pdf:   return shrinkPDF(input, target: target, before: before, job: job)
    case .video: return shrinkVideo(input, target: target, before: before, job: job)
    case .audio: return shrinkAudio(input, target: target, before: before, job: job)
    default:     return Outcome(error: "This file type can't be sized")
    }
}

// Images: native ImageIO. Lowers JPEG quality first (down to a floor), then reduces resolution.

func flatten(_ img: CGImage) -> CGImage? {
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    let r = CGRect(x: 0, y: 0, width: w, height: h)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(r)
    ctx.interpolationQuality = .high
    ctx.draw(img, in: r)
    return ctx.makeImage()
}

func jpegData(_ img: CGImage, quality: Double) -> Data? {
    let d = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(d, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest) ? (d as Data) : nil
}

func shrinkImage(_ input: URL, target: Int64, before: Int64, job: Job) -> Outcome {
    guard let src = CGImageSourceCreateWithURL(input as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int else { return Outcome(error: "Can't read this image") }
    let longSide = max(w, h)
    let goal = Int(target)

    func render(_ factor: Double) -> CGImage? {
        let px = max(32, min(longSide, Int(Double(longSide) * factor)))
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                  kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: px,
                                  kCGImageSourceShouldCacheImmediately: true]
        guard let t = CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary) else { return nil }
        return flatten(t)
    }

    var result: Data?
    var smallest: Data?
    let factors: [Double] = [1, 0.85, 0.7, 0.55, 0.42, 0.32, 0.24, 0.17, 0.12, 0.08]
    for f in factors {
        if job.cancelled { return Outcome(error: "Cancelled") }
        guard let img = render(f), let low = jpegData(img, quality: 0.5) else { continue }
        if smallest == nil || low.count < smallest!.count { smallest = low }
        if low.count > goal { continue }
        var best = low, lo = 0.5, hi = 0.92
        if let top = jpegData(img, quality: hi), top.count <= goal { best = top }
        else {
            for _ in 0..<7 {
                let mid = (lo + hi) / 2
                if let d = jpegData(img, quality: mid), d.count <= goal { best = d; lo = mid } else { hi = mid }
            }
        }
        result = best
        break
    }
    var reached = true
    if result == nil {                                  // last resort: smallest size, very low quality
        reached = false
        if let img = render(factors.last!) {
            for q in [0.3, 0.15, 0.05] {
                if let d = jpegData(img, quality: q) {
                    if smallest == nil || d.count < smallest!.count { smallest = d }
                    if d.count <= goal { result = d; reached = true; break }
                }
            }
        }
        if result == nil { result = smallest }
    }
    guard let data = result else { return Outcome(error: "Couldn't encode image") }
    let tmp = makeTemp(); defer { try? FileManager.default.removeItem(at: tmp) }
    let f = tmp.appendingPathComponent("img.jpg")
    do { try data.write(to: f) } catch { return Outcome(error: "Couldn't write image") }
    return commit(f, input: input, ext: "jpg", before: before, reached: reached && Int64(data.count) <= target)
}

// PDF: Ghostscript image downsampling ladder, binary-searched for the gentlest setting that fits.

func shrinkPDF(_ input: URL, target: Int64, before: Int64, job: Job) -> Outcome {
    guard let gsPath = locate("gs") else { return Outcome(error: "Missing tool. In Terminal run: brew install ghostscript") }
    let tmp = makeTemp(); defer { try? FileManager.default.removeItem(at: tmp) }
    let ladder = [250, 200, 150, 120, 96, 72, 55, 40]
    var cache: [Int: (URL, Int64)] = [:]

    func attempt(_ i: Int) -> (URL, Int64)? {
        if let c = cache[i] { return c }
        let dpi = ladder[i]
        let out = tmp.appendingPathComponent("p\(i).pdf")
        let r = runTool(gsPath, [
            "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=/ebook",
            "-dNOPAUSE", "-dBATCH", "-dQUIET", "-dDetectDuplicateImages=true", "-dCompressFonts=true",
            "-dDownsampleColorImages=true", "-dColorImageDownsampleType=/Bicubic",
            "-dColorImageResolution=\(dpi)", "-dColorImageDownsampleThreshold=1.0",
            "-dDownsampleGrayImages=true", "-dGrayImageDownsampleType=/Bicubic",
            "-dGrayImageResolution=\(dpi)", "-dGrayImageDownsampleThreshold=1.0",
            "-dDownsampleMonoImages=true", "-dMonoImageDownsampleType=/Subsample",
            "-dMonoImageResolution=\(max(dpi, 150))",
            "-sOutputFile=\(out.path)", input.path], job: job)
        guard r.status == 0, FileManager.default.fileExists(atPath: out.path) else { return nil }
        let v = (out, fileSize(out)); cache[i] = v; return v
    }

    let last = ladder.count - 1
    guard let strongest = attempt(last) else {
        return Outcome(error: job.cancelled ? "Cancelled" : "Ghostscript failed")
    }
    var pick = strongest
    let reached = strongest.1 <= target
    if reached {
        var lo = 0, hi = last
        while lo < hi {
            if job.cancelled { return Outcome(error: "Cancelled") }
            let mid = (lo + hi) / 2
            if let a = attempt(mid), a.1 <= target { hi = mid; pick = a } else { lo = mid + 1 }
        }
    }
    return commit(pick.0, input: input, ext: "pdf", before: before, reached: reached)
}

// Video: two-pass H.264 at a bitrate computed from duration, with up to 2 corrective retries.

func probeDuration(_ fp: String, _ path: String, job: Job) -> Double {
    let r = runTool(fp, ["-v", "error", "-show_entries", "format=duration",
                         "-of", "default=noprint_wrappers=1:nokey=1", path], job: job)
    return Double(r.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

func shrinkVideo(_ input: URL, target: Int64, before: Int64, job: Job) -> Outcome {
    guard let ffm = locate("ffmpeg"), let fp = locate("ffprobe") else {
        return Outcome(error: "Missing tool. In Terminal run: brew install ffmpeg")
    }
    let dur = probeDuration(fp, input.path, job: job)
    if job.cancelled { return Outcome(error: "Cancelled") }
    guard dur > 0.2 else { return Outcome(error: "Can't read video length") }
    let audio = runTool(fp, ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type",
                             "-of", "csv=p=0", input.path], job: job).out.contains("audio")

    let totalBps = Double(target) * 8 * 0.93 / dur
    let abps = audio ? Int(min(128_000, max(32_000, totalBps * 0.12))) : 0
    let tmp = makeTemp(); defer { try? FileManager.default.removeItem(at: tmp) }
    var factor = 1.0
    var best: (URL, Int64)?

    for attempt in 0..<3 {
        if job.cancelled { return Outcome(error: "Cancelled") }
        let vb = Int(max(30_000, (totalBps - Double(abps)) * factor))
        let cap: Int? = vb >= 3_000_000 ? nil : vb >= 1_200_000 ? 1080 : vb >= 500_000 ? 720 : vb >= 220_000 ? 480 : 360
        let vf = cap.map { "scale=-2:min(ih\\,\($0))" } ?? "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        let log = tmp.appendingPathComponent("pass\(attempt)").path
        let out = tmp.appendingPathComponent("v\(attempt).mp4")

        let p1 = runTool(ffm, ["-y", "-nostdin", "-i", input.path, "-map", "0:v:0", "-vf", vf,
                               "-c:v", "libx264", "-preset", "fast", "-b:v", "\(vb)", "-pix_fmt", "yuv420p",
                               "-pass", "1", "-passlogfile", log, "-an", "-f", "null", "/dev/null"], job: job)
        guard p1.status == 0 else { return Outcome(error: job.cancelled ? "Cancelled" : lastLine(p1.err)) }

        var a2 = ["-y", "-nostdin", "-i", input.path, "-map", "0:v:0"]
        if audio { a2 += ["-map", "0:a:0"] }
        a2 += ["-vf", vf, "-c:v", "libx264", "-preset", "fast", "-b:v", "\(vb)",
               "-maxrate", "\(Int(Double(vb) * 1.5))", "-bufsize", "\(vb * 2)", "-pix_fmt", "yuv420p",
               "-pass", "2", "-passlogfile", log]
        a2 += audio ? ["-c:a", "aac", "-b:a", "\(abps)"] : ["-an"]
        a2 += ["-movflags", "+faststart", out.path]
        let p2 = runTool(ffm, a2, job: job)
        guard p2.status == 0 else { return Outcome(error: job.cancelled ? "Cancelled" : lastLine(p2.err)) }

        let size = fileSize(out)
        if best == nil || size < best!.1 { best = (out, size) }
        if size <= target || vb <= 30_000 { break }
        factor *= Double(target) / Double(max(size, 1)) * 0.96
    }
    guard let b = best else { return Outcome(error: "Compression failed") }
    return commit(b.0, input: input, ext: "mp4", before: before, reached: b.1 <= target)
}

// Audio: MP3 at a bitrate computed from duration.

func shrinkAudio(_ input: URL, target: Int64, before: Int64, job: Job) -> Outcome {
    guard let ffm = locate("ffmpeg"), let fp = locate("ffprobe") else {
        return Outcome(error: "Missing tool. In Terminal run: brew install ffmpeg")
    }
    let dur = probeDuration(fp, input.path, job: job)
    if job.cancelled { return Outcome(error: "Cancelled") }
    guard dur > 0.2 else { return Outcome(error: "Can't read audio length") }
    let tmp = makeTemp(); defer { try? FileManager.default.removeItem(at: tmp) }
    var br = Double(target) * 8 * 0.96 / dur
    var best: (URL, Int64)?

    for attempt in 0..<2 {
        if job.cancelled { return Outcome(error: "Cancelled") }
        let b = Int(min(320_000, max(24_000, br)))
        let out = tmp.appendingPathComponent("a\(attempt).mp3")
        var a = ["-y", "-nostdin", "-i", input.path, "-vn", "-map", "0:a:0", "-c:a", "libmp3lame", "-b:a", "\(b)"]
        if b < 64_000 { a += ["-ar", "22050"] }
        if b < 48_000 { a += ["-ac", "1"] }
        a.append(out.path)
        let r = runTool(ffm, a, job: job)
        guard r.status == 0 else { return Outcome(error: job.cancelled ? "Cancelled" : lastLine(r.err)) }
        let size = fileSize(out)
        if best == nil || size < best!.1 { best = (out, size) }
        if size <= target || b <= 24_000 { break }
        br *= Double(target) / Double(max(size, 1)) * 0.96
    }
    guard let b = best else { return Outcome(error: "Compression failed") }
    return commit(b.0, input: input, ext: "mp3", before: before, reached: b.1 <= target)
}

// MARK: - Small UI components

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}

struct SpinnerRing: View {
    @State private var spin = false
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(AngularGradient(colors: [Color.accentColor.opacity(0), Color.accentColor],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(100)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: 40, height: 40)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

struct DoneBadge: View {
    let warn: Bool
    @State private var go = false
    var body: some View {
        let c: Color = warn ? .orange : .green
        ZStack {
            Circle().fill(c.opacity(0.18))
                .frame(width: 52, height: 52)
                .scaleEffect(go ? 1 : 0.5)
                .opacity(go ? 1 : 0)
            Image(systemName: warn ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(c)
                .symbolEffect(.bounce, value: go)
        }
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { go = true } }
    }
}

struct HelpCard: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 17)).foregroundStyle(Color.accentColor)
                Text("DropWheel").font(.system(size: 16, weight: .bold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 8) {
                row("square.and.arrow.down", "Drop one or many files onto the wheel")
                row("hand.tap", "Click a wedge, or press its number")
                row("scalemass", "Set Size compresses to an exact KB or MB")
                row("ellipsis.circle", "More › has rename, zip, sort, AirDrop, mail")
            }
            Divider().opacity(0.5)
            VStack(spacing: 7) {
                shortcut("Open or close", ["fn", "⌥ Space"])
                shortcut("Pick an action", ["1–9", "0"])
                shortcut("Paste files or screenshot", ["⌘V"])
                shortcut("Back, or close", ["esc"])
            }
            HStack(spacing: 14) {
                legend(Color.accentColor, "Convert")
                legend(Color.green, "Compress")
                Spacer()
                Text("Press H to toggle").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 290)
        .glassCard(22)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ label: String, _ keys: [String]) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            ForEach(keys, id: \.self) { KeyCap(text: $0) }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 10.5, weight: .medium))
        }
    }
}

// MARK: - Wedge item

struct WedgeItem: View {
    let action: WheelAction
    let index: Int
    let count: Int
    let hot: Bool
    let size: CGFloat
    let inner: CGFloat
    let outer: CGFloat

    @State private var shown = false

    private let corner: CGFloat = 7
    private let gap: CGFloat = 3

    var body: some View {
        let step = 360.0 / Double(count)
        let s = Angle.degrees(-90 + step * Double(index))
        let e = Angle.degrees(-90 + step * Double(index + 1))
        let mid = (s.radians + e.radians) / 2
        let ux = CGFloat(cos(mid)), uy = CGFloat(sin(mid))
        let r = (inner + outer) / 2 + 1
        let tint: Color = action.compress ? Color.green : Color.accentColor
        let shape = Wedge(start: s, end: e, inner: inner, outer: outer, gap: gap, round: corner)
        let stroke = StrokeStyle(lineWidth: corner * 2, lineJoin: .round)
        let restPaint: Color = action.compress ? Color.green : Color.primary
        let restOpacity: Double = action.compress ? 0.15 : 0.07
        let hotPaint = RadialGradient(colors: [tint.opacity(0.80), tint], center: .center,
                                      startRadius: inner, endRadius: outer)
        let pop: CGFloat = hot ? 6 : 0

        ZStack {
            // Resting surface (composited as one layer so the fill and rounded stroke don't double up).
            ZStack {
                shape.fill(restPaint)
                shape.stroke(restPaint, style: stroke)
            }
            .compositingGroup()
            .opacity(restOpacity)

            // Highlight surface, faded in on hover.
            ZStack {
                shape.fill(hotPaint)
                shape.stroke(hotPaint, style: stroke)
            }
            .compositingGroup()
            .opacity(hot ? 1 : 0)
            .shadow(color: tint.opacity(hot ? 0.45 : 0), radius: 12, y: 3)

            VStack(spacing: 4) {
                Image(systemName: action.icon).font(.system(size: 19, weight: .medium))
                Text(action.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(hot ? Color.white : Color.primary)
            .shadow(color: .black.opacity(hot ? 0.25 : 0), radius: 2, y: 1)
            .scaleEffect(hot ? 1.06 : 1)
            .position(x: size / 2 + ux * r, y: size / 2 + uy * r)

            if index < 10 {
                Text(index == 9 ? "0" : "\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(hot ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                    .position(x: size / 2 + ux * (outer - 12), y: size / 2 + uy * (outer - 12))
            }
        }
        .frame(width: size, height: size)
        .offset(x: ux * pop, y: uy * pop)
        .scaleEffect(shown ? 1 : 0.75)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hot)
        .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(index) * 0.025), value: shown)
        .onAppear { shown = true }
        .transition(.opacity)
    }
}

// MARK: - Target size card

struct SizeCard: View {
    let files: [URL]
    let onStart: (Int64) -> Void
    let onBack: () -> Void

    enum Unit: String, CaseIterable {
        case kb = "KB", mb = "MB"
        var bytes: Double { self == .kb ? 1_000 : 1_000_000 }
    }
    @State private var text = ""
    @State private var unit: Unit = .mb
    @FocusState private var focused: Bool

    private var sizes: [Int64] { files.map(fileSize) }
    private var ref: Int64 { max(sizes.min() ?? 1, 1) }

    private var target: Int64? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        let b = v * unit.bytes
        return (b.isFinite && b >= 1_000 && b < 1e12) ? Int64(b) : nil
    }
    private var canRun: Bool {
        guard let t = target else { return false }
        return t < (sizes.max() ?? 0)
    }
    private var ratio: Double {
        guard let t = target else { return 0.5 }
        return min(max(Double(t) / Double(ref), 0.02), 1)
    }
    private var hint: String {
        guard let t = target else { return "Enter a size, for example 500 KB or 2 MB" }
        if !canRun { return "That isn’t smaller than the original" }
        if files.count > 1 { return "Each file will be at most \(human(t))" }
        let pct = Int((1 - Double(t) / Double(ref)) * 100)
        return "About \(pct)% smaller"
    }
    private var tip: String {
        switch kind(of: files[0]) {
        case .image: return "Adjusts quality, then resolution. Saved as JPG."
        case .video: return "Two-pass H.264 encode. Saved as MP4, usually within a few % of target."
        case .audio: return "Saved as MP3 at the bitrate that fits."
        case .pdf:   return "Downsamples images. Text-only PDFs may not shrink much."
        default:     return ""
        }
    }
    private let presets: [Int64] = [50_000, 100_000, 250_000, 500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000, 25_000_000]
    private var chips: [Int64] { Array(presets.filter { $0 < ref }.suffix(8)) }

    private func setTarget(_ b: Int64) {
        if b >= 1_000_000 {
            unit = .mb
            var s = String(format: "%.2f", Double(b) / 1_000_000)
            while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
            text = s
        } else {
            unit = .kb
            text = String(max(1, Int((Double(b) / 1_000).rounded())))
        }
    }
    private var fraction: Binding<Double> {
        Binding(get: { ratio }, set: { setTarget(Int64(Double(ref) * $0)) })
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            inputField
            sizeBar
            Slider(value: fraction, in: 0.02...1).tint(Color.green)

            if !chips.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(chips, id: \.self) { b in chip(b) }
                }
            }

            VStack(spacing: 3) {
                Text(hint)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(canRun || target == nil ? Color.secondary : Color.orange)
                if !tip.isEmpty { Text(tip).font(.caption2).foregroundStyle(.tertiary) }
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered).controlSize(.large)
                Button { if let t = target, canRun { onStart(t) } } label: {
                    Text("Compress").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
            }
        }
        .padding(22)
        .frame(width: 390)
        .glassCard(26)
        .onAppear {
            setTarget(max(ref / 2, 1_000))
            DispatchQueue.main.async { focused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                .resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compress to size").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(files.count > 1 ? "\(files.count) files, each to the target"
                                     : "\(files[0].lastPathComponent)  ·  \(human(sizes[0]))")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            TextField("0", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .focused($focused)
            Picker("", selection: $unit) {
                ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 88)
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                              lineWidth: focused ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    /// Visual before/after: the green bar is the target relative to the original.
    private var sizeBar: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.green.opacity(0.65), Color.green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * CGFloat(ratio)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: ratio)
                }
            }
            .frame(height: 7)
            HStack {
                Text(target.map { human($0) } ?? "–")
                    .foregroundStyle(canRun ? Color.green : Color.secondary)
                Spacer()
                Text(files.count > 1 ? "smallest: \(human(ref))" : "original: \(human(ref))")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
        }
    }

    private func chip(_ b: Int64) -> some View {
        let selected = target == b
        return Button { setTarget(b) } label: {
            Text(human(b))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rename card

struct RenameCard: View {
    let files: [URL]
    let onStart: (String, Int, Bool) -> Void
    let onBack: () -> Void

    @State private var pattern = "{name}"
    @State private var start = 1
    @State private var slug = false
    @FocusState private var focused: Bool

    private func newName(_ i: Int) -> String {
        renamedName(files[i], index: i, total: files.count, pattern: pattern, start: start, slug: slug)
    }
    private var canRun: Bool {
        if pattern.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return files.indices.contains { newName($0) != files[$0].lastPathComponent }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            field
            HStack(spacing: 6) {
                ForEach(["{name}", "{n}", "{date}"], id: \.self) { t in
                    Button { pattern += t } label: {
                        Text(t)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Clear") { pattern = "" }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Stepper("Number from \(start)", value: $start, in: 0...9999)
                    .font(.system(size: 12))
                Spacer()
                Toggle("Clean names", isOn: $slug)
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            }
            previewBox
            Text("{name} original name  ·  {n} counter  ·  {date} file date")
                .font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered).controlSize(.large)
                Button { if canRun { onStart(pattern, start, slug) } } label: {
                    Text(files.count > 1 ? "Rename \(files.count) files" : "Rename").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
            }
        }
        .padding(22)
        .frame(width: 390)
        .glassCard(26)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                .resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rename").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(files.count > 1 ? "\(files.count) files" : files[0].lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var field: some View {
        TextField("{name}", text: $pattern)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium, design: .monospaced))
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                                  lineWidth: focused ? 2 : 1)
            )
    }

    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(files.prefix(3).enumerated()), id: \.offset) { i, f in
                HStack(spacing: 6) {
                    Text(f.lastPathComponent).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(newName(i)).foregroundStyle(Color.accentColor)
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.system(size: 11))
            }
            if files.count > 3 {
                Text("+ \(files.count - 3) more").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Main view

enum Phase: Equatable {
    case idle
    case help
    case choosing([URL])
    case sizing([URL])
    case renaming([URL])
    case running(String)
    case done(String, Bool)      // note, warning
    case failed(String)
}

struct WheelView: View {
    @State private var phase: Phase = .idle
    @State private var targeted = false
    @State private var hovered: String?
    @State private var busy = false
    @State private var job: Job?
    @State private var appear = false
    @State private var page = 0

    private let size: CGFloat = AppDelegate.panelSize
    private let inner: CGFloat = 84
    private let outer: CGFloat = 200

    private var isCard: Bool {
        switch phase {
        case .sizing, .renaming: return true
        default: return false
        }
    }

    /// Up to 9 actions per page plus a "More ›" wedge when there are more than 10 in total.
    private func pageList(_ files: [URL]) -> [WheelAction] {
        let all = wheelList(files)
        guard all.count > 10 else { return all }
        let pages = Int((Double(all.count) / 9.0).rounded(.up))
        let p = page % pages
        let slice = Array(all[(p * 9)..<min(all.count, (p + 1) * 9)])
        return slice + [act(moreID, "ellipsis.circle", "-", ext: nil, args: { _, _ in [] })]
    }

    var body: some View {
        ZStack {
            wheelLayer
            if case .sizing(let files) = phase {
                SizeCard(files: files,
                         onStart: { runTarget(files, target: $0) },
                         onBack: { phase = .choosing(files) })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if case .renaming(let files) = phase {
                RenameCard(files: files,
                           onStart: { p, s, c in runRename(files, pattern: p, start: s, slug: c) },
                           onBack: { phase = .choosing(files) })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(appear ? 1 : 0.9)
        .opacity(appear ? 1 : 0)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: handleDrop)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .onChange(of: hovered) { _, new in
            if new != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelReset)) { _ in
            if !busy { phase = .idle; hovered = nil; page = 0 }
            appear = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appear = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelHelp)) { _ in
            if busy { return }
            if phase == .help { phase = .idle } else if phase == .idle { phase = .help }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelEsc)) { _ in
            if busy { NotificationCenter.default.post(name: .wheelClose, object: nil); return }
            if case .sizing(let f) = phase { phase = .choosing(f) }
            else if case .renaming(let f) = phase { phase = .choosing(f) }
            else { NotificationCenter.default.post(name: .wheelClose, object: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelPick)) { n in
            if case .choosing(let files) = phase, let i = n.object as? Int {
                let list = pageList(files)
                if i >= 1 && i <= list.count { choose(list[i - 1], files) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelPaste)) { _ in
            guard !busy else { return }
            switch phase {
            case .idle, .choosing, .help, .failed:
                let f = pasteboardFiles()
                if !f.isEmpty { page = 0; hovered = nil; phase = .choosing(f) }
            default:
                break
            }
        }
    }

    // MARK: Wheel layer

    private var base: some View {
        let d = outer * 2 + 8
        return ZStack {
            Circle().fill(.regularMaterial)
            Circle().fill(glassSheen)
            Circle().strokeBorder(glassRim, lineWidth: 1)
            // Drop-target glow
            Circle().strokeBorder(Color.accentColor, lineWidth: 9).blur(radius: 10)
                .opacity(targeted ? 0.55 : 0)
            Circle().strokeBorder(Color.accentColor, lineWidth: 3)
                .opacity(targeted ? 1 : 0)
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.30), radius: 28, y: 12)
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }

    var wheelLayer: some View {
        ZStack {
            base

            if case .choosing(let files) = phase { wedges(for: files) }

            center

            if phase == .help { HelpCard { phase = .idle } }
            if phase == .idle { helpButton }
        }
        .frame(width: size, height: size)
        .opacity(isCard ? 0 : 1)
        .scaleEffect(isCard ? 0.97 : 1)
        .allowsHitTesting(!isCard)
        .contentShape(Rectangle())
        .onContinuousHover { hp in
            guard case .choosing(let files) = phase else { hovered = nil; return }
            switch hp {
            case .active(let loc):
                let list = pageList(files)
                hovered = wedgeIndex(at: loc, count: list.count).map { list[$0].id }
            case .ended:
                hovered = nil
            }
        }
        .gesture(SpatialTapGesture().onEnded { v in
            guard case .choosing(let files) = phase else { return }
            let list = pageList(files)
            if let i = wedgeIndex(at: v.location, count: list.count) { choose(list[i], files) }
            else if hypot(v.location.x - size / 2, v.location.y - size / 2) < inner { phase = .idle }
        })
    }

    // MARK: Help button

    var helpButton: some View {
        Button { phase = .help } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 17)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .position(x: size / 2, y: size / 2 + outer - 32)
    }

    // MARK: Wedges

    @ViewBuilder
    func wedges(for files: [URL]) -> some View {
        let list = pageList(files)
        ForEach(Array(list.enumerated()), id: \.element.id) { idx, action in
            WedgeItem(action: action, index: idx, count: list.count,
                      hot: hovered == action.id, size: size, inner: inner, outer: outer)
        }
    }

    // MARK: Center

    var center: some View {
        ZStack {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle().fill(glassSheen)
                Circle().strokeBorder(glassRim, lineWidth: 0.8)
            }
            .frame(width: inner * 2 - 14, height: inner * 2 - 14)
            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            .scaleEffect(targeted ? 1.04 : 1)

            switch phase {
            case .idle:
                VStack(spacing: 6) {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(targeted ? Color.accentColor : Color.secondary)
                        .symbolEffect(.pulse, isActive: !targeted)
                    Text(targeted ? "Release to open" : "Drop files")
                        .font(.system(size: 13, weight: .medium))
                    Text("esc to close").font(.system(size: 9)).opacity(0.6)
                }
                .foregroundStyle(.secondary)
                .scaleEffect(targeted ? 1.08 : 1)

            case .choosing(let files):
                VStack(spacing: 4) {
                    if let h = hovered {
                        Text(h).font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(h == moreID ? "click for more" : "click to run")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                            .resizable().frame(width: 44, height: 44)
                        Text(files.count > 1 ? "\(files.count) files" : files[0].lastPathComponent)
                            .font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                        Text(human(files.map(fileSize).reduce(0, +)))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112)

            case .running(let name):
                VStack(spacing: 8) {
                    SpinnerRing()
                    Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text("tap to cancel").font(.system(size: 9)).foregroundStyle(.secondary).opacity(0.7)
                }
                .frame(width: 120)
                .contentShape(Circle())
                .onTapGesture { job?.cancel() }

            case .done(let note, let warn):
                VStack(spacing: 5) {
                    DoneBadge(warn: warn)
                    Text("Done").font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(width: 118)
                }

            case .help, .sizing, .renaming:
                EmptyView()

            case .failed(let msg):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28)).foregroundStyle(.orange)
                    Text(msg).font(.system(size: 10)).multilineTextAlignment(.center)
                        .frame(width: 118).lineLimit(5)
                    Text("tap to retry").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .contentShape(Circle())
                .onTapGesture { phase = .idle }
            }
        }
    }

    func wedgeIndex(at p: CGPoint, count: Int) -> Int? {
        let dx = p.x - size / 2, dy = p.y - size / 2
        let r = hypot(dx, dy)
        guard count > 0, r >= inner, r <= outer else { return nil }
        var deg = atan2(dy, dx) * 180 / .pi + 90
        if deg < 0 { deg += 360 }
        return min(Int(deg / (360.0 / Double(count))), count - 1)
    }

    // MARK: Logic

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if busy { return false }
        let box = URLBox()
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    if let url { box.urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let files = box.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if !files.isEmpty && !busy { hovered = nil; page = 0; phase = .choosing(files) }
        }
        return true
    }

    /// Wedge clicked: open the size card, flip to the next page, or run straight away.
    func choose(_ action: WheelAction, _ all: [URL]) {
        guard !busy else { return }
        if action.id == moreID {
            hovered = nil
            page += 1
            return
        }
        if action.renaming {
            hovered = nil
            phase = .renaming(all)
            return
        }
        if action.sizing {
            let k = kind(of: all[0])
            hovered = nil
            phase = .sizing(all.filter { kind(of: $0) == k })
        } else {
            run(action, on: all)
        }
    }

    func run(_ action: WheelAction, on all: [URL]) {
        guard !busy else { return }

        // Batch tools work on everything that was dropped, whatever the file types.
        if let b = action.batch {
            runBatch(action.title, all, b)
            return
        }

        let k = kind(of: all[0])
        let files = all.filter { kind(of: $0) == k }
        let skipped = all.count - files.count

        // Native actions need no external tool.
        var tool = ""
        if action.native == nil {
            guard let t = locate(action.tool) else {
                phase = .failed(action.brew.isEmpty ? "Missing tool: \(action.tool)"
                                                    : "Missing tool. In Terminal run: brew install \(action.brew)")
                return
            }
            tool = t
        }

        if action.id == "Merge" || action.id == "Combine to PDF" {
            let joined = files.map { $0.path }.joined(separator: "\u{1}")
            launch(action.title, files: [files[0]], skipped: 0, compress: false, trash: false) { input, job in
                convert(action, tool: tool, input: input, inputPath: joined, job: job)
            }
        } else {
            launch(action.title, files: files, skipped: skipped, compress: action.compress, trash: true) { input, job in
                convert(action, tool: tool, input: input, job: job)
            }
        }
    }

    func runRename(_ files: [URL], pattern: String, start: Int, slug: Bool) {
        runBatch("Renaming", files) { f, job in
            renameFiles(f, pattern: pattern, start: start, slug: slug, job: job)
        }
    }

    func runBatch(_ title: String, _ files: [URL], _ work: @escaping ([URL], Job) -> BatchResult) {
        guard !busy else { return }
        let job = Job()
        self.job = job
        busy = true; hovered = nil
        phase = .running(title + "…")
        DispatchQueue.global(qos: .userInitiated).async {
            let r = work(files, job)
            DispatchQueue.main.async {
                busy = false
                self.job = nil
                if job.cancelled { phase = .failed("Cancelled"); return }
                if let e = r.error { phase = .failed(e); playSound("Basso"); return }
                phase = .done(r.note, false)
                afterDone(r.outs, warn: false)
            }
        }
    }

    /// Sound, reveal in Finder, copy to clipboard, then close the wheel.
    func afterDone(_ outs: [URL], warn: Bool) {
        playSound(warn ? "Funk" : "Glass")
        if !outs.isEmpty {
            if UserDefaults.standard.object(forKey: "reveal") as? Bool ?? true {
                NSWorkspace.shared.activateFileViewerSelecting(outs)
            }
            if UserDefaults.standard.bool(forKey: "copyResult") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(outs as [NSURL])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (warn ? 4.0 : 2.2)) {
            if case .done = phase { NotificationCenter.default.post(name: .wheelClose, object: nil) }
        }
    }

    func runTarget(_ files: [URL], target: Int64) {
        guard !busy else { return }
        launch("Compressing", files: files, skipped: 0, compress: true, trash: true) { input, job in
            compressToTarget(input, target: target, job: job)
        }
    }

    func launch(_ title: String, files: [URL], skipped: Int, compress: Bool, trash: Bool,
                work: @escaping (URL, Job) -> Outcome) {
        let job = Job()
        self.job = job
        busy = true; hovered = nil
        phase = .running(files.count > 1 ? "\(title) 1/\(files.count)" : title + "…")
        let trashOriginal = UserDefaults.standard.bool(forKey: "trashOriginal")

        DispatchQueue.global(qos: .userInitiated).async {
            var outs: [URL] = [], failed = 0, err = "", missed = 0, unchanged = 0
            var before: Int64 = 0, after: Int64 = 0

            for (n, input) in files.enumerated() {
                if job.cancelled { break }
                if files.count > 1 {
                    DispatchQueue.main.async { phase = .running("\(title) \(n + 1)/\(files.count)") }
                }
                let r = work(input, job)
                if let u = r.url {
                    outs.append(u); before += r.before; after += r.after
                    if !r.reached { missed += 1 }
                    if u == input { unchanged += 1 }
                    else if trash && trashOriginal {
                        // Never trash the original when the result is a folder (Split / All Pages / Extract).
                        let isFolder = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                        if !isFolder { try? FileManager.default.trashItem(at: input, resultingItemURL: nil) }
                    }
                } else { failed += 1; err = r.error }
            }

            DispatchQueue.main.async {
                busy = false
                self.job = nil
                if job.cancelled { phase = .failed("Cancelled"); return }
                if outs.isEmpty {
                    phase = .failed(err.isEmpty ? "Something went wrong" : err)
                    playSound("Basso")
                    return
                }
                var note = outs.count > 1 ? "\(outs.count) files" : human(after)
                var warn = false
                if compress {
                    note = (unchanged == outs.count && missed == 0) ? "Already optimal"
                         : "\(human(before)) → \(human(after))"
                }
                if missed > 0 { warn = true; note += "\nTarget not reachable" }
                if failed > 0 { warn = true; note += "\n\(failed) failed" }
                if skipped > 0 { note += "\n\(skipped) skipped (other type)" }
                phase = .done(note, warn)
                afterDone(outs, warn: warn)
            }
        }
    }
}

