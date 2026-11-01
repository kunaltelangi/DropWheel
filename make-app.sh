#!/bin/bash
# Builds DropWheel.app (and DropWheel.dmg) from DropWheel.swift. No Xcode project needed.
# Usage:  ./make-app.sh
# Requires: Xcode or Command Line Tools installed (xcode-select --install)

set -euo pipefail
cd "$(dirname "$0")"

NAME="DropWheel"
SRC="DropWheel.swift"
BUILD="build"
APP="$BUILD/$NAME.app"
BUNDLE_ID="com.dropwheel.app"
VERSION="1.0"

[ -f "$SRC" ] || { echo "Put $SRC in the same folder as this script."; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling (arm64)..."
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  "$SRC" -o "$BUILD/$NAME-arm64"

echo "Compiling (x86_64)..."
swiftc -O -parse-as-library -swift-version 5 -target x86_64-apple-macos14.0 \
  "$SRC" -o "$BUILD/$NAME-x86_64"

echo "Combining into one universal app..."
lipo -create "$BUILD/$NAME-arm64" "$BUILD/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
rm "$BUILD/$NAME-arm64" "$BUILD/$NAME-x86_64"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Generating app icon..."
ICONDIR="$BUILD/icon-work"
mkdir -p "$ICONDIR/AppIcon.iconset"

cat > "$ICONDIR/icongen.swift" <<'SWIFT'
import AppKit
import ImageIO

// Draws a 1024x1024 app icon: gradient squircle with a wheel of 8 wedges and a center hub.
let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// macOS icon grid: 824pt squircle centered in 1024pt canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
              color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(CGColor(red: 0.20, green: 0.35, blue: 0.95, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Gradient fill.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [CGColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 1),
              CGColor(red: 0.45, green: 0.25, blue: 0.90, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
// Top sheen.
let sheen = [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray
let sg = CGGradient(colorsSpace: cs, colors: sheen, locations: [0, 1])!
ctx.drawLinearGradient(sg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 512), options: [])

// Wheel.
let c = CGPoint(x: 512, y: 512)
let rOuter: CGFloat = 290, rInner: CGFloat = 135
let n = 8
let gap = 4.0 * Double.pi / 180
for i in 0..<n {
    let step = 2 * Double.pi / Double(n)
    let a0 = Double(i) * step + gap / 2 + Double.pi / 8
    let a1 = Double(i + 1) * step - gap / 2 + Double.pi / 8
    let p = CGMutablePath()
    p.addArc(center: c, radius: rOuter, startAngle: a0, endAngle: a1, clockwise: false)
    p.addArc(center: c, radius: rInner, startAngle: a1, endAngle: a0, clockwise: true)
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(CGColor(gray: 1, alpha: i == 0 ? 0.97 : (i % 2 == 0 ? 0.62 : 0.40)))
    ctx.fillPath()
}
// Hub.
ctx.setFillColor(CGColor(gray: 1, alpha: 0.96))
ctx.fillEllipse(in: CGRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
ctx.setFillColor(CGColor(red: 0.38, green: 0.40, blue: 0.95, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68))
ctx.restoreGState()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
                                                 "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
SWIFT

ICON_OK=0
if swiftc -O "$ICONDIR/icongen.swift" -o "$ICONDIR/icongen" 2>/dev/null \
   && "$ICONDIR/icongen" "$ICONDIR/icon.png" 2>/dev/null \
   && [ -s "$ICONDIR/icon.png" ]; then
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONDIR/icon.png" --out "$ICONDIR/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICONDIR/icon.png" --out "$ICONDIR/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  if iconutil -c icns "$ICONDIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    ICON_OK=1
  fi
fi
if [ "$ICON_OK" -ne 1 ]; then
  echo "  (icon generation failed - continuing without a custom icon)"
fi
rm -rf "$ICONDIR"

echo "Signing..."
# If you have a developer certificate, replace "-" with its name for a stable signature
# (a stable signature keeps the Accessibility / Input Monitoring permissions across rebuilds).
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

echo "Creating DMG..."
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$BUILD/$NAME.dmg"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$BUILD/$NAME.dmg" >/dev/null

echo
echo "Done!"
echo "  App: $(pwd)/$APP"
echo "  DMG: $(pwd)/$BUILD/$NAME.dmg"
echo
echo "Next: drag the app to /Applications and open it from there."
echo "If macOS says it can't be opened: right-click the app > Open, or run:"
echo "  xattr -cr /Applications/$NAME.app"
