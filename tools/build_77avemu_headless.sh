#!/usr/bin/env bash
# Build tools/77avemu_headless.cpp against an existing 77AVEMU CMake build.
#
# Usage:
#   tools/build_77avemu_headless.sh /tmp/fm7-77avemu-build
#
# The build directory must already contain the normal Mutsu_CUI target.  The
# script reuses CMake's generated include and link settings, so it does not
# duplicate 77AVEMU's long platform-specific library list.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=${1:?usage: $0 77avemu-build-dir [output]}
OUT=${2:-"$BUILD/fm77av_headless"}
FLAGS="$BUILD/main_cui/CMakeFiles/Mutsu_CUI.dir/flags.make"
LINK="$BUILD/main_cui/CMakeFiles/Mutsu_CUI.dir/link.txt"
OBJ="$BUILD/fm77av_headless.o"

test -f "$FLAGS" || { echo "missing $FLAGS (build 77AVEMU first)" >&2; exit 1; }
test -f "$LINK" || { echo "missing $LINK (build 77AVEMU first)" >&2; exit 1; }

defines=$(sed -n 's/^CMAKE_CXX_COMPILER:FILEPATH=//p' "$BUILD/CMakeCache.txt" | head -1)
compiler=${defines:-c++}
compiler=${compiler:-c++}
includes=$(sed -n 's/^CXX_INCLUDES = //p' "$FLAGS")
cxxflags=$(sed -n 's/^CXX_FLAGS = //p' "$FLAGS")

"$compiler" $cxxflags $includes -c "$HERE/77avemu_headless.cpp" -o "$OBJ"

# link.txt is relative to the main_cui build directory.  Keep the generated
# object outside that directory but replace only Mutsu_CUI's main object and
# output path.
link=$(sed \
  -e "s#CMakeFiles/Mutsu_CUI.dir/main.cpp.o#$OBJ#" \
  -e "s#-o Mutsu_CUI.app/Contents/MacOS/Mutsu_CUI#-o $OUT#" \
  "$LINK")
(cd "$BUILD/main_cui" && eval "$link")
echo "$OUT"
