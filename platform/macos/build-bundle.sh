#!/usr/bin/env sh
# Shared compilation and bundle assembly. Source this from build-app.sh or build-pkg.sh
# after setting ROOT and OUT. It sets NAME, APP (staging) and FINAL_APP for the caller.

if [ "$(uname -s)" != Darwin ]; then
    echo "macOS app packaging requires macOS" >&2
    exit 1
fi

for tool in odin xcrun cmake git ar iconutil plutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing build tool: $tool (see README.md, macOS app)" >&2
        exit 1
    fi
done

NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$ROOT/platform/macos/Info.plist")
FINAL_APP="$OUT/$NAME.app"
APP="$OUT/$NAME.build.app"
MIN_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/platform/macos/Info.plist")
DEPS="$ROOT/external/macos/arm64-$MIN_MACOS"
# Pin SDL rather than depending on a Homebrew installation. Override to match newer Odin bindings.
SDL_VERSION=${SDL_VERSION:-3.4.16}
SDL_DEPS="$DEPS/sdl-$SDL_VERSION"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/platform/macos/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/platform/macos/Info.plist"))"

mkdir -p "$DEPS" "$OUT"

# The native libraries are built once into external/macos for the oldest macOS the app runs on, the ones
# `just setup` and Odin ship are built for the Mac they were built on. SDL is linked in statically,
# Homebrew's isn't on the Macs the app runs on.
ODIN_ROOT=$(odin root)
CC="xcrun clang -target arm64-apple-macos$MIN_MACOS"
CFLAGS="-O2 -fPIC"

if [ ! -f "$DEPS/libpffft.a" ]; then
    echo "Building pffft"
    $CC $CFLAGS -c "$ROOT/external/pffft/pffft.c" -o "$DEPS/pffft.o"
    ar rcs "$DEPS/libpffft.a" "$DEPS/pffft.o"
fi

if [ ! -f "$DEPS/libpa_ringbuffer.a" ]; then
    echo "Building pa_ringbuffer"
    $CC $CFLAGS -c "$ROOT/external/portaudio/src/common/pa_ringbuffer.c" -o "$DEPS/pa_ringbuffer.o"
    ar rcs "$DEPS/libpa_ringbuffer.a" "$DEPS/pa_ringbuffer.o"
fi

if [ ! -f "$DEPS/libminiaudio.a" ]; then
    echo "Building miniaudio"
    mkdir -p "$DEPS/miniaudio"
    for src in "$ODIN_ROOT"/vendor/miniaudio/src/*.c; do
        $CC $CFLAGS -c "$src" -o "$DEPS/miniaudio/$(basename "$src" .c).o"
    done
    ar rcs "$DEPS/libminiaudio.a" "$DEPS"/miniaudio/*.o
fi

mkdir -p "$SDL_DEPS"
if [ ! -d "$SDL_DEPS/SDL" ]; then
    git -c advice.detachedHead=false clone --depth 1 --branch "release-$SDL_VERSION" https://github.com/libsdl-org/SDL "$SDL_DEPS/SDL"
fi
if [ ! -f "$SDL_DEPS/sdl3/lib/libSDL3.a" ]; then
    echo "Building SDL"
    cmake -S "$SDL_DEPS/SDL" -B "$SDL_DEPS/SDL/build" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$SDL_DEPS/sdl3" \
        -DSDL_SHARED=OFF \
        -DSDL_STATIC=ON \
        -DSDL_TEST_LIBRARY=OFF \
        -DSDL_EXAMPLES=OFF
    cmake --build "$SDL_DEPS/SDL/build" --config Release --parallel
    cmake --install "$SDL_DEPS/SDL/build" --config Release
fi

# No -microarch:native, the build has to run on every Apple silicon Mac, not only this one. Odin only emits an
# object file, clang links it with the static libraries, Odin would link Homebrew's SDL.
echo "Compiling app"
odin build "$ROOT/src/app" \
    -build-mode:obj \
    -use-single-module \
    -target:darwin_arm64 \
    -minimum-os-version:$MIN_MACOS \
    -define:VERSION="$VERSION" \
    -o:speed \
    -vet \
    -out:"$OUT/app.o"

# Assemble afresh so a local bundle never retains a profile, entitlements or old signatures.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Linking"
$CC \
    "$OUT/app.o" \
    "$DEPS/libpffft.a" \
    "$DEPS/libpa_ringbuffer.a" \
    "$DEPS/libminiaudio.a" \
    "$ODIN_ROOT/vendor/stb/lib/darwin/stb_image.a" \
    "$ODIN_ROOT/vendor/stb/lib/darwin/stb_truetype.a" \
    "$ODIN_ROOT/vendor/stb/lib/darwin/stb_rect_pack.a" \
    "$SDL_DEPS/sdl3/lib/libSDL3.a" \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework Cocoa \
    -weak_framework UniformTypeIdentifiers \
    -framework IOKit \
    -framework ForceFeedback \
    -framework Carbon \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework AVFoundation \
    -framework Foundation \
    -framework GameController \
    -framework Metal \
    -framework QuartzCore \
    -weak_framework CoreHaptics \
    -o "$APP/Contents/MacOS/app.bin"

cp "$ROOT/platform/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/platform/macos/Credits.rtf" "$APP/Contents/Resources/"
cp "$ROOT/assets/Acknowledgements.txt" "$APP/Contents/Resources/"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/"
# The App Store wants the 1024px icon_512x512@2x.png in the set
iconutil -c icns "$ROOT/platform/macos/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

