#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/.build}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
APP_PATH="$OUTPUT_DIR/CCF Deadline.app"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swift-cache"
cd "$PROJECT_DIR"
BINARIES=()
for ARCH in arm64 x86_64; do
    swift build --build-system native --disable-sandbox --cache-path "$BUILD_DIR/package-cache" --scratch-path "$BUILD_DIR" -c release --arch "$ARCH" \
        -debug-info-format none \
        -Xswiftc -file-prefix-map -Xswiftc "$PROJECT_DIR=/src/CCFDeadline" \
        -Xswiftc -file-prefix-map -Xswiftc "$BUILD_DIR=/build/CCFDeadline" \
        -Xswiftc -debug-prefix-map -Xswiftc "$PROJECT_DIR=/src/CCFDeadline" \
        -Xswiftc -debug-prefix-map -Xswiftc "$BUILD_DIR=/build/CCFDeadline"
    BIN_DIR="$(swift build --build-system native --disable-sandbox --cache-path "$BUILD_DIR/package-cache" --scratch-path "$BUILD_DIR" -c release --arch "$ARCH" --show-bin-path)"
    BINARIES+=("$BIN_DIR/CCFDeadline")
done
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
xcrun lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/CCFDeadline"
# Remove local symbol/debug metadata before signing the distributable binary.
xcrun strip -S -x "$APP_PATH/Contents/MacOS/CCFDeadline"
cp "$PROJECT_DIR/Sources/CCFDeadline/Resources/seed.json" "$APP_PATH/Contents/Resources/seed.json"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.txt" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$PROJECT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then cp "$PROJECT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"; fi
xattr -cr "$APP_PATH"
python3 "$PROJECT_DIR/scripts/audit-release.py" "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf 'Built: %s\n' "$APP_PATH"
