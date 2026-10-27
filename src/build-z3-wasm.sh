#!/usr/bin/env bash
# Build a single-threaded Z3 WebAssembly module for z3-shim.js.
#
# Usage: ./build-z3-wasm.sh <z3-source-dir> [output-dir]
#
# Requires Emscripten (emcc, emcmake) on PATH. Tested with Z3 tag z3-4.16.0.
# Produces <output-dir>/z3-built.js and <output-dir>/z3-built.wasm.
#
# Why not the official npm package (z3-solver)? Its WASM is a pthreads build
# and needs SharedArrayBuffer, which VS Code webviews do not get by default.
# Z3 itself links fine single-threaded (its own WASM recipe builds libz3 with
# Z3_SINGLE_THREADED=ON; only its JS async wrapper needs threads).
set -euo pipefail

SRC="${1:?usage: $0 <z3-source-dir> [output-dir]}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)}"
SRC="$(cd "$SRC" && pwd)"
OUT="$(cd "$OUT" && pwd)"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Z3_POLLING_TIMER: without it, resource limits and the first unsat answer try
# to start a std::thread, which fails in a threadless WebAssembly module.
#
# Exception handling: Z3 uses C++ exceptions throughout, so both the objects
# and the link need JS-based exception catching enabled (same flags as Z3's
# own build-wasm.ts, minus pthreads).
EH_FLAGS="-fexceptions -s DISABLE_EXCEPTION_CATCHING=0"

echo "--- configuring Z3 (single-threaded, static) in $SRC/build-wasm"
if [ ! -f "$SRC/build-wasm/CMakeCache.txt" ]; then
  CXXFLAGS="$EH_FLAGS" emcmake cmake -S "$SRC" -B "$SRC/build-wasm" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DZ3_BUILD_LIBZ3_SHARED=OFF \
    -DZ3_SINGLE_THREADED=ON \
    -DZ3_POLLING_TIMER=ON \
    -DZ3_BUILD_EXECUTABLE=OFF \
    -DZ3_BUILD_TEST_EXECUTABLES=OFF \
    -DZ3_BUILD_PYTHON_BINDINGS=OFF \
    -DZ3_ENABLE_EXAMPLE_TARGETS=OFF \
    -DZ3_INCLUDE_GIT_HASH=OFF \
    -DZ3_INCLUDE_GIT_DESCRIBE=OFF
fi

echo "--- building libz3.a with $JOBS jobs"
cmake --build "$SRC/build-wasm" --target libz3 --parallel "$JOBS"

# The exported C entry points. The shim drives Z3 entirely through SMT-LIB2
# text (Z3_eval_smtlib2_string), so only context management is needed.
EXPORTS='["_malloc","_free","_Z3_mk_config","_Z3_del_config","_Z3_set_param_value","_Z3_mk_context","_Z3_del_context","_Z3_eval_smtlib2_string","_Z3_get_version","_Z3_global_param_set","_Z3_get_error_code","_Z3_get_error_msg","_Z3_update_param_value","_z3shim_install_error_handler"]'
METHODS='["ccall","cwrap","UTF8ToString","stringToUTF8","lengthBytesUTF8","getValue","getExceptionMessage"]'

echo "--- linking z3-built.js / z3-built.wasm into $OUT"
# shellcheck disable=SC2086
em++ "$HERE/z3-shim-native.c" "$SRC/build-wasm/libz3.a" \
  -O2 $EH_FLAGS \
  -I "$SRC/src/api" \
  -s MODULARIZE=1 \
  -s 'EXPORT_NAME="initZ3"' \
  -s ENVIRONMENT=web,worker,node \
  -s EXPORTED_FUNCTIONS="$EXPORTS" \
  -s EXPORTED_RUNTIME_METHODS="$METHODS" \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s MAXIMUM_MEMORY=4GB \
  -s INITIAL_MEMORY=128MB \
  -s STACK_SIZE=20MB \
  -s ALLOW_TABLE_GROWTH=1 \
  -s EXIT_RUNTIME=0 \
  -s EXPORT_EXCEPTION_HANDLING_HELPERS=1 \
  -s NODEJS_CATCH_EXIT=0 \
  -s NODEJS_CATCH_REJECTION=0 \
  -o "$OUT/z3-built.js"

echo "--- done"
ls -la "$OUT/z3-built.js" "$OUT/z3-built.wasm"
