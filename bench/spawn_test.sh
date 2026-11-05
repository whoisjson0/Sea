#!/bin/sh
# bench/spawn_test.sh -- self-test of the exec-and-wait helper bench/spawn_time.c (DESIGN.md
# 2.17.4, "The helper"). POSIX sh; macOS (xcrun cc) and Linux (gcc).
#
# usage: sh bench/spawn_test.sh
#
# Builds bench/spawn_time.c into a private temporary directory with the flags of the benchmark
# (`xcrun cc -O2 -ffp-contract=off` on the Mac, `gcc -O2 -ffp-contract=off` on Linux) and checks:
#   true      /usr/bin/true: status 0, wall below 0.1 s
#   exit3     sh -c 'exit 3': status 3
#   signal    sh -c 'kill -TERM $$': status 143 (128 + SIGTERM)
#   sleep     sleep 0.2: wall within [0.2, 0.4) s, cpu below 0.05 s
#   busy      a busy shell loop of about 0.5 s: cpu at least half the wall
#   streams   a child writing to both streams: OUT and ERR hold exactly its bytes
#   stdin     the child's standard input is /dev/null (cat reads nothing)
#   cwd       the child runs in DIR
#   env       the child gets the helper's environment unchanged
#   format    the helper's standard output is exactly one line `wall %.9f cpu %.9f status %d`
#   noprog    a missing program: exit 2, nothing on standard output
#   nodir     a missing DIR: exit 2, nothing on standard output
#   usage     a usage error (no `--`, too few arguments, a relative path): exit 2, nothing on
#             standard output
# Output: `FAIL <case>: <reason>` per failure, then `spawn test: P passed, F failed`.
# Exit status: 0 all passed, 1 a failure, 2 setup error (no compiler, the build failed).

LC_ALL=C; export LC_ALL
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/sea-spawntest.XXXXXX") || { echo "spawn_test.sh: cannot create a temporary directory" >&2; exit 2; }
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; exit 2' HUP INT TERM PIPE

if [ "$(uname -s)" = Darwin ]; then CC="xcrun cc"; else CC=gcc; fi
# shellcheck disable=SC2086
$CC -O2 -ffp-contract=off -o "$T/spawn_time" "$ROOT/bench/spawn_time.c" 2>"$T/cc.err" || {
    echo "spawn_test.sh: building spawn_time.c with $CC failed:" >&2
    sed 's/^/    /' "$T/cc.err" >&2
    exit 2
}
ST=$T/spawn_time
mkdir "$T/d" || exit 2

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1: $2"; }

# spawn PROG [ARG...] : run the helper in $T/d with OUT $T/out and ERR $T/err; its standard output
# goes to $T/res, its status to $SST; W, C and S are the line's wall, cpu and status (empty when the
# line is malformed)
spawn() {
    "$ST" "$T/d" "$T/out" "$T/err" -- "$@" >"$T/res" 2>"$T/res.err"
    SST=$?
    W=; C=; S=
    if [ "$(wc -l <"$T/res" | tr -d ' ')" = 1 ] \
        && grep -Eq '^wall [0-9]+\.[0-9]{9} cpu [0-9]+\.[0-9]{9} status [0-9]+$' "$T/res"; then
        set -- $(cat "$T/res")
        W=$2; C=$4; S=$6
    fi
}

# measured NAME : the helper exited 0 with a well-formed line (else a failure, return 1)
measured() {
    if [ "$SST" -ne 0 ]; then bad "$1" "helper exit status $SST: $(head -2 "$T/res.err" | tr '\n' ' ')"; return 1; fi
    if [ -z "$S" ]; then bad "$1" "malformed result line '$(head -2 "$T/res" | tr '\n' '|')'"; return 1; fi
    return 0
}

# lt A B : A < B as decimal numbers
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }

spawn /usr/bin/true
if measured true; then
    if [ "$S" != 0 ]; then bad true "status $S, want 0"
    elif ! lt "$W" 0.1; then bad true "wall $W, want below 0.1"
    else ok; fi
fi

spawn /bin/sh -c 'exit 3'
if measured exit3; then
    if [ "$S" = 3 ]; then ok; else bad exit3 "status $S, want 3"; fi
fi

spawn /bin/sh -c 'kill -TERM $$'
if measured signal; then
    if [ "$S" = 143 ]; then ok; else bad signal "status $S, want 143"; fi
fi

spawn /bin/sleep 0.2
if measured sleep; then
    if [ "$S" != 0 ]; then bad sleep "status $S, want 0"
    elif lt "$W" 0.2 || ! lt "$W" 0.4; then bad sleep "wall $W, want within [0.2, 0.4)"
    elif ! lt "$C" 0.05; then bad sleep "cpu $C, want below 0.05"
    else ok; fi
fi

spawn /bin/sh -c 'i=0; while [ $i -lt 300000 ]; do i=$((i+1)); done'
if measured busy; then
    if [ "$S" != 0 ]; then bad busy "status $S, want 0"
    elif lt "$C" "$(awk -v w="$W" 'BEGIN { printf "%.9f", w / 2 }')"; then bad busy "cpu $C below half the wall $W"
    else ok; fi
fi

printf 'to stdout\nsecond line' >"$T/want.out"
printf 'to stderr\n' >"$T/want.err"
spawn /bin/sh -c 'printf "to stdout\n"; printf "to stderr\n" >&2; printf "second line"'
if measured streams; then
    if [ "$S" != 0 ]; then bad streams "status $S, want 0"
    elif ! cmp -s "$T/out" "$T/want.out"; then bad streams "OUT does not hold exactly the child's standard output"
    elif ! cmp -s "$T/err" "$T/want.err"; then bad streams "ERR does not hold exactly the child's standard error"
    else ok; fi
fi

# OUT and ERR are truncated: a second, silent child leaves both empty
spawn /bin/sh -c 'cat; printf x'
if measured stdin; then
    if [ "$S" != 0 ]; then bad stdin "status $S, want 0"
    elif [ "$(cat "$T/out")" != x ] || [ -s "$T/err" ]; then bad stdin "standard input is not empty, or OUT/ERR were not truncated"
    else ok; fi
fi

spawn /bin/sh -c 'pwd -P'
if measured cwd; then
    if [ "$(cat "$T/out")" = "$T/d" ]; then ok; else bad cwd "the child ran in '$(cat "$T/out")', want '$T/d'"; fi
fi

SPAWN_TEST_VALUE='a b=c'; export SPAWN_TEST_VALUE
spawn /bin/sh -c 'printf "%s" "$SPAWN_TEST_VALUE"'
unset SPAWN_TEST_VALUE
if measured env; then
    if [ "$(cat "$T/out")" = 'a b=c' ]; then ok; else bad env "the child saw '$(cat "$T/out")'"; fi
fi

spawn /usr/bin/true
if measured format; then
    if grep -Eqx 'wall [0-9]+\.[0-9]{9} cpu [0-9]+\.[0-9]{9} status 0' "$T/res" \
        && [ "$(wc -c <"$T/res" | tr -d ' ')" = "$(head -1 "$T/res" | wc -c | tr -d ' ')" ]; then ok
    else bad format "standard output is not exactly one result line"; fi
fi

# failures of the helper itself: exit 2 and nothing on standard output
fails() {
    _n=$1; shift
    "$ST" "$@" >"$T/res" 2>"$T/res.err"
    _st=$?
    if [ $_st -ne 2 ]; then bad "$_n" "exit status $_st, want 2"
    elif [ -s "$T/res" ]; then bad "$_n" "something on standard output"
    elif [ ! -s "$T/res.err" ]; then bad "$_n" "no message on standard error"
    else ok; fi
}
fails noprog "$T/d" "$T/out" "$T/err" -- "$T/no-such-program"
fails nodir "$T/no-such-dir" "$T/out" "$T/err" -- /usr/bin/true
fails usage "$T/d" "$T/out" "$T/err" /usr/bin/true
fails usage "$T/d" "$T/out" "$T/err" --
fails usage d "$T/out" "$T/err" -- /usr/bin/true

echo "spawn test: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
exit 0
