#!/usr/bin/env bash
#
# mayhem/build.sh — build the hevcesbrowser fuzz harness, its standalone reproducer, and the
# known-answer runners mayhem/test.sh uses to check the parser against upstream's own test suite
# (hevcparser/tests/Parsing.cpp, run as mayhem/oracle/observe.cpp: the same suite with the expected
# half of every assertion removed, so no answer is compiled into any program built here).
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# exports the build contract (CC, CXX, LIB_FUZZING_ENGINE, SANITIZER_FLAGS, DEBUG_FLAGS,
# STANDALONE_FUZZ_MAIN, SRC). This script is idempotent and air-gapped: every dependency
# is baked into the image by the Dockerfile, so a `--network none` re-run succeeds.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

CXXSTD="-std=c++11"
PARSER_INC="-I$SRC/hevcparser/include"
PARSER_SRCS=(
  hevcparser/src/HevcParser.cpp
  hevcparser/src/Hevc.cpp
  hevcparser/src/HevcParserImpl.cpp
  hevcparser/src/BitstreamReader.cpp
  hevcparser/src/HevcUtils.cpp
)
ORACLE="$SRC/mayhem/oracle"
# observe.cpp finds "kat.h" and "Params.h" next to it in mayhem/oracle/; "Hevc.h"/"HevcParser.h"
# come from the (patched) tree. Those headers may redefine anything observe.cpp uses, but there is
# no answer in it to hand back: the answers are only in expected.txt, which only test.sh reads.
ORACLE_INC="$PARSER_INC"
# The project's normal flags: upstream CMakeLists.txt in a Release build (-std=c++11, -fPIC on
# Linux, CMake's Release -O3 -DNDEBUG).
NORMAL_FLAGS="-O3 -DNDEBUG -fPIC $COVERAGE_FLAGS"
# The graded parser objects also carry SanitizerCoverage (-fsanitize=fuzzer-no-link), unconditionally
# (also when $SANITIZER_FLAGS is empty): $LIB_FUZZING_ENGINE only instruments the harness TU it is
# compiled with, so without this libFuzzer/Mayhem would see the harness's edges and none of the
# parser's. Coverage instrumentation only adds counters and comparison callbacks; it changes no
# parser behaviour. Everything linking these objects is linked with the same flag (a no-op next to
# ASan, whose runtime already provides the callbacks; it pulls in the sanitizer runtime that does
# when $SANITIZER_FLAGS is empty).
GRADED_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link"
# The graded flags (coverage included) with UBSan reports made non-fatal (nothing else differs, no
# runtime options): for the one sample stream that reaches a real signed overflow in the parser
# (see test.sh). The twin must carry the coverage flag too: otherwise code keyed on it (e.g.
# `#if __has_feature(coverage_sanitizer)`) would differ between the graded binary and the only
# sanitized runner that checks that stream (#1460).
TWIN_FLAGS="$GRADED_FLAGS -fsanitize-recover=undefined"

BUILD_FUZZ="$SRC/build-fuzz"     # graded objects, the fuzz targets and the graded-flags runners
BUILD_TESTS="$SRC/build-tests"   # the normal-flags runner
rm -rf "$BUILD_FUZZ" "$BUILD_TESTS"
mkdir -p "$BUILD_FUZZ" "$BUILD_TESTS"

# run_parallel <command>... : run the shell commands, $MAYHEM_JOBS at a time; fail if any fails.
run_parallel() {
  printf '%s\0' "$@" | xargs -0 -n1 -P "$MAYHEM_JOBS" bash -c 'set -e; eval "$1"' _
}

# ---------------------------------------------------------------------------
# 1) Compile everything that has no dependency, in parallel:
#    - the parser library instrumented with $GRADED_FLAGS ($SANITIZER_FLAGS + coverage) and
#      $DEBUG_FLAGS (so the FUZZED code — not just the harness — is sanitized, coverage-instrumented
#      and carries DWARF < 4 symbols). These are the graded objects; the graded-flags known-answer
#      runner links these same objects;
#    - the parser library with TWIN_FLAGS (graded flags, coverage included, plus
#      -fsanitize-recover=undefined), and with the project's normal flags;
#    - the known-answer runner sources (mayhem/oracle/observe.cpp + kat_main.cpp) with the graded
#      flags (coverage included: observe.cpp includes the tree's headers, so their inline code
#      must be the same flavour as the graded objects' copies) and with the normal flags.
# ---------------------------------------------------------------------------
cmds=()
gobjs=(); wobjs=(); nobjs=()
for s in "${PARSER_SRCS[@]}"; do
  b="$(basename "${s%.cpp}")"
  cmds+=("$CXX $CXXSTD $GRADED_FLAGS $DEBUG_FLAGS $PARSER_INC -fPIC -c $s -o $BUILD_FUZZ/$b.o")
  cmds+=("$CXX $CXXSTD $TWIN_FLAGS $DEBUG_FLAGS $PARSER_INC -fPIC -c $s -o $BUILD_FUZZ/$b.twin.o")
  cmds+=("$CXX $CXXSTD $NORMAL_FLAGS $PARSER_INC -c $s -o $BUILD_TESTS/$b.o")
  gobjs+=("$BUILD_FUZZ/$b.o"); wobjs+=("$BUILD_FUZZ/$b.twin.o"); nobjs+=("$BUILD_TESTS/$b.o")
done
for s in observe kat_main; do
  cmds+=("$CXX $CXXSTD $GRADED_FLAGS $DEBUG_FLAGS $ORACLE_INC -c $ORACLE/$s.cpp -o $BUILD_FUZZ/kat_$s.o")
  cmds+=("$CXX $CXXSTD $NORMAL_FLAGS $ORACLE_INC -c $ORACLE/$s.cpp -o $BUILD_TESTS/kat_$s.o")
done
# Build-time LeakSanitizer off-switch (SPEC.md section 6.2 item 15), linked into the fuzz target,
# its standalone reproducer and the two sanitized known-answer runners. (Its own header comment
# predates the fuzz-target linkage and says the fuzz binaries do not link it; that file is pinned
# by SHA-256 in test.sh, so it is left byte-identical. This line is the current fact.)
cmds+=("$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c $ORACLE/lsan_off.cc -o $BUILD_FUZZ/lsan_off.o")
# C++ harness: compile the standalone driver as a C object first so its
# LLVMFuzzerTestOneInput reference keeps C linkage (clang++ would mangle it).
cmds+=("$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c $STANDALONE_FUZZ_MAIN -o $BUILD_FUZZ/standalone_main.o")
run_parallel "${cmds[@]}"
ar rcs "$BUILD_FUZZ/libhevcparser.a" "${gobjs[@]}"

# ---------------------------------------------------------------------------
# 2) Link, in parallel:
#    - the libFuzzer harness (target: hevcesbrowser-console) and a standalone, non-fuzzer
#      reproducer over the same harness;
#    - the known-answer runners mayhem/test.sh drives. None of them holds an answer or decides a
#      verdict: they print the parser-side values of the suite's assertions; test.sh judges them.
#        build-fuzz/hevc_kat       graded flags, linked with the graded objects (libhevcparser.a)
#        build-fuzz/hevc_kat_twin  TWIN_FLAGS parser objects (graded flags + UBSan recover)
#        build-tests/hevc_kat      the project's normal flags
# ---------------------------------------------------------------------------
KAT_G="$BUILD_FUZZ/kat_observe.o $BUILD_FUZZ/kat_kat_main.o $BUILD_FUZZ/lsan_off.o"
run_parallel \
  "$CXX $CXXSTD $GRADED_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $PARSER_INC $SRC/mayhem/fuzz_hevcparser.cpp $BUILD_FUZZ/lsan_off.o $BUILD_FUZZ/libhevcparser.a -o /mayhem/hevcesbrowser-console" \
  "$CXX $CXXSTD $GRADED_FLAGS $DEBUG_FLAGS $PARSER_INC $SRC/mayhem/fuzz_hevcparser.cpp $BUILD_FUZZ/standalone_main.o $BUILD_FUZZ/lsan_off.o $BUILD_FUZZ/libhevcparser.a -o /mayhem/hevcesbrowser-console-standalone" \
  "$CXX $GRADED_FLAGS $DEBUG_FLAGS $KAT_G $BUILD_FUZZ/libhevcparser.a -o $BUILD_FUZZ/hevc_kat" \
  "$CXX $TWIN_FLAGS $DEBUG_FLAGS $KAT_G ${wobjs[*]} -o $BUILD_FUZZ/hevc_kat_twin" \
  "$CXX $NORMAL_FLAGS $BUILD_TESTS/kat_observe.o $BUILD_TESTS/kat_kat_main.o ${nobjs[*]} -o $BUILD_TESTS/hevc_kat"

echo "build.sh: done"
