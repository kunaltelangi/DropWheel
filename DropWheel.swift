import SwiftUI
import UniformTypeIdentifiers
import AppKit
import ImageIO
import ServiceManagement
import ApplicationServices

// DropWheel requires macOS 14+, Swift 5 language mode, App Sandbox OFF.

extension Notification.Name {
    static let wheelReset = Notification.Name("dropwheel.reset")
    static let wheelHelp  = Notification.Name("dropwheel.help")
    static let wheelPick  = Notification.Name("dropwheel.pick")
    static let wheelClose = Notification.Name("dropwheel.close")
    static let wheelEsc   = Notification.Name("dropwheel.esc")
}

// MARK: App (menu bar + hotkeys)

@main
struct DropWheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @AppStorage("trashOriginal") private var trashOriginal = false
    @AppStorage("sound") private var sound = true

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
    static let panelSize: CGFloat = 500

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
        NotificationCenter.default.post(name: .wheelReset, object: nil)
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.frame {
            let h = AppDelegate.panelSize / 2
            panel.setFrameOrigin(NSPoint(x: f.midX - h, y: f.midY - h))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { panel.orderOut(nil) }

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
    let args: (_ input: String, _ output: String) -> [String]
}

func act(_ title: String, _ icon: String, _ tool: String, brew: String = "", ext: String?,
         suffix: String = "", temp: Bool = false, compress: Bool = false, sizing: Bool = false,
         args: @escaping (String, String) -> [String]) -> WheelAction {
    WheelAction(title: title, icon: icon, tool: tool, brew: brew, ext: ext, suffix: suffix,
                temp: temp, compress: compress, sizing: sizing, args: args)
}

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
    let zip = act("Zip", "doc.zipper", "ditto", ext: "zip") { i, o in ["-c", "-k", "--keepParent", i, o] }

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
            // Removes EXIF: GPS location, camera, date. Great before sharing photos online.
            ff("Strip Info", "location.slash", nil, suffix: "-clean") { i, o in
                ["-y", "-i", i, "-map_metadata", "-1", "-c", "copy", o] },
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
            list = [act("Extract", "archivebox", "ditto", ext: "") { i, o in ["-x", "-k", i, o] }]
        } else if e == "7z" || e == "rar" {
            list = [act("Extract", "archivebox", "7zz", brew: "sevenzip", ext: "") { i, o in ["x", i, "-o" + o, "-y"] }]
        } else {
            list = [act("Extract", "archivebox", "sh", ext: "") { i, o in ["-c", "mkdir -p \"$2\" && tar -xf \"$1\" -C \"$2\"", "_", i, o] }]
        }
    case .data:
        list = [
            act("Pretty", "text.alignleft", "sh", ext: nil, suffix: "-pretty") { i, o in ["-c", "python3 -m json.tool \"$1\" > \"$2\"", "_", i, o] },
            act("Minify", "arrow.down.right.and.arrow.up.left", "sh", ext: nil, suffix: "-min") { i, o in
                ["-c", "python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(\",\", \":\")))' \"$1\" > \"$2\"", "_", i, o] },
            zip
        ]
    case .other:
        list = [zip]
    }
    return list.filter { !($0.suffix.isEmpty && $0.ext == e) }
        // "Strip Info" uses ffmpeg stream copy, which is only reliable for these formats.
        .filter { $0.id != "Strip Info" || ["jpg", "png", "webp"].contains(e) }
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
    return l
}

// MARK: - Helpers

func playSound(_ name: String) {
    if UserDefaults.standard.object(forKey: "sound") as? Bool ?? true { NSSound(named: name)?.play() }
}

/// Folder inside the app that holds the packed tools (ffmpeg, Ghostscript, qpdf, ...).
/// nil when the app was built without packed tools (developer / Xcode builds).
let bundledBin: String? = {
    guard let r = Bundle.main.resourcePath else { return nil }
    let p = r + "/bin"
    return FileManager.default.fileExists(atPath: p) ? p : nil
}()

/// Message shown when a tool can't be found.
func missingToolText(_ formula: String, title: String = "") -> String {
    if bundledBin == nil && !formula.isEmpty { return "Missing tool. In Terminal run: brew install \(formula)" }
    if formula.hasPrefix("--cask libreoffice") { return "Needs LibreOffice (free at libreoffice.org)" }
    if formula == "ocrmypdf" || formula.contains("pdf2docx") {
        return title.isEmpty ? "This feature needs a tool that isn't included" : "\(title) needs a tool that isn't included"
    }
    return "A built-in tool is missing. Please reinstall DropWheel."
}

func locate(_ tool: String) -> String? {
    let fm = FileManager.default
    if tool.hasPrefix("/") { return fm.isExecutableFile(atPath: tool) ? tool : nil }
    if let b = bundledBin, fm.isExecutableFile(atPath: b + "/" + tool) { return b + "/" + tool }
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

// MARK: - Wedge shape

struct Wedge: Shape {
    var start: Angle, end: Angle
    var inner: CGFloat, outer: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
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
    var pathParts = ["/opt/homebrew/bin", "/usr/local/bin"]
    if let b = bundledBin { pathParts.insert(b, at: 0) }
    env["PATH"] = pathParts.joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
    // Ghostscript packed inside the app needs to find its own resource files.
    if let r = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: r + "/gs") {
        let g = r + "/gs"
        env["GS_LIB"] = [g + "/Resource/Init", g + "/lib", g + "/Resource/Font",
                         g + "/iccprofiles", g + "/fonts"].joined(separator: ":")
    }
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

// MARK: - Normal conversion

func convert(_ action: WheelAction, tool: String, input: URL, inputPath: String? = nil, job: Job) -> Outcome {
    let fm = FileManager.default
    let output = uniqueOutput(for: input, suffix: action.suffix, ext: action.ext)
    let tmp = makeTemp()
    let work = tmp.appendingPathComponent("out")
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

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
            return Outcome(error: missingToolText(action.brew, title: action.title))
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
    guard let gsPath = locate("gs") else { return Outcome(error: missingToolText("ghostscript")) }
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
        return Outcome(error: missingToolText("ffmpeg"))
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
        return Outcome(error: missingToolText("ffmpeg"))
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
    private var hint: String {
        guard let t = target else { return "Enter a size, for example 500 KB or 2 MB" }
        if !canRun { return "That isn’t smaller than the original" }
        if files.count > 1 { return "Each file will be at most \(human(t))" }
        let pct = Int((1 - Double(t) / Double(ref)) * 100)
        return "About \(pct)% smaller  ·  \(human(sizes[0])) → \(human(t))"
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
        Binding(get: {
            guard let t = target else { return 0.5 }
            return min(max(Double(t) / Double(ref), 0.02), 1)
        }, set: { setTarget(Int64(Double(ref) * $0)) })
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compress to size").font(.headline)
                    Text(files.count > 1 ? "\(files.count) files · each to the target"
                                         : "\(files[0].lastPathComponent) · \(human(sizes[0]))")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("0", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary))
                Picker("", selection: $unit) {
                    ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 92)
            }

            Slider(value: fraction, in: 0.02...1)

            if !chips.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(chips, id: \.self) { b in
                        Button { setTarget(b) } label: { Text(human(b)).frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            VStack(spacing: 3) {
                Text(hint).font(.callout).foregroundStyle(canRun || target == nil ? Color.secondary : Color.orange)
                if !tip.isEmpty { Text(tip).font(.caption2).foregroundStyle(.tertiary) }
            }
            .multilineTextAlignment(.center)

            HStack {
                Button("Back") { onBack() }
                Spacer()
                Button("Compress") { if let t = target, canRun { onStart(t) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .onAppear {
            setTarget(max(ref / 2, 1_000))
            DispatchQueue.main.async { focused = true }
        }
    }
}

// MARK: - Main view

enum Phase: Equatable {
    case idle
    case help
    case choosing([URL])
    case sizing([URL])
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

    private let size: CGFloat = AppDelegate.panelSize
    private let inner: CGFloat = 84
    private let outer: CGFloat = 200

    private var isSizing: Bool { if case .sizing = phase { return true }; return false }

    var body: some View {
        ZStack {
            wheelLayer
            if case .sizing(let files) = phase {
                SizeCard(files: files,
                         onStart: { runTarget(files, target: $0) },
                         onBack: { phase = .choosing(files) })
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: handleDrop)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .onReceive(NotificationCenter.default.publisher(for: .wheelReset)) { _ in
            if !busy { phase = .idle; hovered = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelHelp)) { _ in
            if busy { return }
            if phase == .help { phase = .idle } else if phase == .idle { phase = .help }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelEsc)) { _ in
            if busy { NotificationCenter.default.post(name: .wheelClose, object: nil); return }
            if case .sizing(let f) = phase { phase = .choosing(f) }
            else { NotificationCenter.default.post(name: .wheelClose, object: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wheelPick)) { n in
            if case .choosing(let files) = phase, let i = n.object as? Int {
                let list = wheelList(files)
                if i >= 1 && i <= list.count { choose(list[i - 1], files) }
            }
        }
    }

    // MARK: Wheel layer

    var wheelLayer: some View {
        ZStack {
            Circle().fill(.regularMaterial)
                .frame(width: outer * 2 + 8, height: outer * 2 + 8)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 8)

            Circle()
                .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: targeted ? 3 : 1)
                .frame(width: outer * 2 + 8, height: outer * 2 + 8)

            if case .choosing(let files) = phase { wedges(for: files) }

            center

            if phase == .help { helpCard }
            if phase == .idle { helpButton }
        }
        .frame(width: size, height: size)
        .opacity(isSizing ? 0 : 1)
        .allowsHitTesting(!isSizing)
        .contentShape(Rectangle())
        .onContinuousHover { hp in
            guard case .choosing(let files) = phase else { hovered = nil; return }
            switch hp {
            case .active(let loc):
                let list = wheelList(files)
                hovered = wedgeIndex(at: loc, count: list.count).map { list[$0].id }
            case .ended:
                hovered = nil
            }
        }
        .gesture(SpatialTapGesture().onEnded { v in
            guard case .choosing(let files) = phase else { return }
            let list = wheelList(files)
            if let i = wedgeIndex(at: v.location, count: list.count) { choose(list[i], files) }
            else if hypot(v.location.x - size / 2, v.location.y - size / 2) < inner { phase = .idle }
        })
    }

    // MARK: Help

    var helpButton: some View {
        Button { phase = .help } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 17)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .position(x: size / 2, y: size / 2 + outer - 32)
    }

    var helpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works").font(.system(size: 15, weight: .bold)).padding(.bottom, 2)
            helpRow("keyboard", "fn or ⌥Space opens / closes the wheel")
            helpRow("square.and.arrow.down", "Drag one or many files onto it")
            helpRow("hand.tap", "Click a wedge, or press 1–9 (0 = 10th)")
            helpRow("scalemass", "Set Size: compress to an exact KB / MB limit")
            helpRow("paintpalette", "Blue = convert · Green = compress")
            helpRow("folder", "Saved next to the original (or the folder you chose)")
            helpRow("xmark.circle", "Click the center to cancel · Esc to close")
            Text("Click anywhere here to close · press H to toggle")
                .font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { phase = .idle }
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    func helpRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(Color.accentColor)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Wedges

    @ViewBuilder
    func wedges(for files: [URL]) -> some View {
        let list = wheelList(files)
        let step = 360.0 / Double(list.count)
        ForEach(Array(list.enumerated()), id: \.element.id) { idx, action in
            let s = Angle.degrees(-90 + step * Double(idx) + 1.5)
            let e = Angle.degrees(-90 + step * Double(idx + 1) - 1.5)
            let mid = (s.radians + e.radians) / 2
            let r = (inner + outer) / 2 + 2
            let isHot = hovered == action.id
            let tint: Color = action.compress ? .green : .accentColor
            let rest: Color = action.compress ? Color.green.opacity(0.16) : Color.primary.opacity(0.07)

            ZStack {
                Wedge(start: s, end: e, inner: inner, outer: outer)
                    .fill(isHot ? tint : rest)
                Wedge(start: s, end: e, inner: inner, outer: outer)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)

                VStack(spacing: 4) {
                    Image(systemName: action.icon).font(.system(size: 20, weight: .medium))
                    Text(action.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(isHot ? Color.white : Color.primary)
                .position(x: size / 2 + cos(mid) * r, y: size / 2 + sin(mid) * r)

                if idx < 9 {
                    Text("\(idx + 1)").font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(isHot ? Color.white.opacity(0.75) : Color.secondary.opacity(0.7))
                        .position(x: size / 2 + cos(mid) * (outer - 11), y: size / 2 + sin(mid) * (outer - 11))
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    // MARK: Center

    var center: some View {
        ZStack {
            Circle().fill(.regularMaterial)
                .frame(width: inner * 2 - 14, height: inner * 2 - 14)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3)

            switch phase {
            case .idle:
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 32, weight: .light))
                    Text("Drop files").font(.system(size: 13, weight: .medium))
                    Text("esc to close").font(.system(size: 9)).opacity(0.6)
                }
                .foregroundStyle(.secondary)
                .scaleEffect(targeted ? 1.1 : 1)

            case .choosing(let files):
                VStack(spacing: 4) {
                    if let h = hovered {
                        Text(h).font(.system(size: 15, weight: .semibold))
                        Text("click to run").font(.system(size: 10)).foregroundStyle(.secondary)
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
                VStack(spacing: 6) {
                    Image(systemName: warn ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(warn ? Color.orange : Color.green)
                    Text("Done").font(.system(size: 13, weight: .medium))
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(width: 118)
                }

            case .help, .sizing:
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
            if !files.isEmpty && !busy { hovered = nil; phase = .choosing(files) }
        }
        return true
    }

    /// Wedge clicked: open the size card, or run straight away.
    func choose(_ action: WheelAction, _ all: [URL]) {
        guard !busy else { return }
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
        guard let tool = locate(action.tool) else {
            phase = .failed(action.brew.isEmpty ? "Missing tool: \(action.tool)"
                                                : missingToolText(action.brew, title: action.title))
            return
        }
        let k = kind(of: all[0])
        let files = all.filter { kind(of: $0) == k }
        let skipped = all.count - files.count

        if action.id == "Merge" {
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
                playSound(warn ? "Funk" : "Glass")
                NSWorkspace.shared.activateFileViewerSelecting(outs)
                DispatchQueue.main.asyncAfter(deadline: .now() + (warn ? 4.0 : 2.2)) {
                    if case .done = phase { NotificationCenter.default.post(name: .wheelClose, object: nil) }
                }
            }
        }
    }
}

struct SpinnerRing: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            }
    }
}
