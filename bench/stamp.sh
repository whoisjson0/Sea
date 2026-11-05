#!/bin/sh
# bench/stamp.sh -- the build stamp of the benchmark drivers (DESIGN.md 2.17.3; 10b review fix C1).
# POSIX sh, macOS.
#
# usage: sh bench/stamp.sh          (from any directory)
#
# Prints, as `key<TAB>value` lines in this order:
#     sea_commit      git -C ROOT rev-parse HEAD
#     baysick_commit  git -C BAYSICK rev-parse HEAD
#     sea_dirty       yes/no: git -C ROOT status --porcelain -- . ':(exclude)bench/results'
#     baysick_dirty   yes/no: git -C BAYSICK status --porcelain -- . ':(exclude)sea'
# then one line `file<TAB><cksum output>` per file of the compiler pipeline, paths relative to the
# Sea repository: build/sea, build/std.sea, build/libsea.a, build/libbaysickrt.a,
# build/errors.inc, build/limits.inc, then every pass executable build/sea?* that exists, sorted by
# name (seacheck seaexpand seafuse seagen_a64 seagen_x64 sealoop sealopt sealower seaname seaopt
# seaparse seavec). Each driver's `build` writes this output to build/bench/<tool>/stamp.txt and
# each `measure` / `--cross` recomputes it and refuses (exit 2, `stale build: ...`) when it differs.
# Environment: BAYSICK (the Baysick checkout, default the parent of the Sea repository).
# Exit status: 0 printed; 2 a listed file is missing or a commit cannot be read.

LC_ALL=C; export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BAYSICK=${BAYSICK:-$(cd "$ROOT/.." && pwd)}
fail() { echo "stamp.sh: $1" >&2; exit 2; }

SC=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || fail "cannot read the Sea commit in '$ROOT'"
BC=$(git -C "$BAYSICK" rev-parse HEAD 2>/dev/null) || fail "cannot read the Baysick commit in '$BAYSICK'"
SD=$(git -C "$ROOT" status --porcelain -- . ':(exclude)bench/results' 2>/dev/null) || fail "git status failed in '$ROOT'"
BD=$(git -C "$BAYSICK" status --porcelain -- . ':(exclude)sea' 2>/dev/null) || fail "git status failed in '$BAYSICK'"
printf 'sea_commit\t%s\n' "$SC"
printf 'baysick_commit\t%s\n' "$BC"
if [ -n "$SD" ]; then printf 'sea_dirty\tyes\n'; else printf 'sea_dirty\tno\n'; fi
if [ -n "$BD" ]; then printf 'baysick_dirty\tyes\n'; else printf 'baysick_dirty\tno\n'; fi

cd "$ROOT" || fail "cannot change to '$ROOT'"
for f in build/sea build/std.sea build/libsea.a build/libbaysickrt.a build/errors.inc build/limits.inc; do
    [ -f "$f" ] || fail "'$ROOT/$f' not found; run 'make' first"
done
PASSES=$(for f in build/sea?*; do [ -f "$f" ] && [ -x "$f" ] && echo "$f"; done | sort)
[ -n "$PASSES" ] || fail "no pass executable build/sea?* found; run 'make' first"
for f in build/sea build/std.sea build/libsea.a build/libbaysickrt.a build/errors.inc build/limits.inc $PASSES; do
    c=$(cksum "$f") || fail "cannot read '$ROOT/$f'"
    printf 'file\t%s\n' "$c"
done
exit 0
