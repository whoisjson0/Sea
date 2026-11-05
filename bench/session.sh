#!/bin/sh
# bench/session.sh -- create the measurement session (DESIGN.md 2.17.3, L-ps). POSIX sh.
#
# usage: sh bench/session.sh DIR [--quick]
#
# Creates DIR (with its parents) and writes DIR/session.txt, one line: the UTC time
# (date -u +%Y%m%dT%H%M%SZ), `-`, and 8 hexadecimal digits from /dev/urandom, for example
# 20261105T091500Z-3fa9c21e. Every driver reads DIR/session.txt and records it.
#   final mode (default): DIR must not exist or be empty (one session is one directory).
#   --quick (also BENCH_QUICK=1): DIR may hold anything; session.txt is replaced and the id is
#           prefixed with `quick-`; but a DIR whose session.txt records a final session (an id
#           without the `quick-` prefix) is refused (C3: a quick run never touches a final
#           session's directory).
# Exit status: 0 written, 2 setup error (usage, DIR not empty in final mode, a final session in
# quick mode, cannot write).

LC_ALL=C; export LC_ALL
QUICK=
[ "${BENCH_QUICK:-}" = 1 ] && QUICK=1
DIR=
while [ $# -gt 0 ]; do
    case $1 in
    --quick) QUICK=1; shift ;;
    -*) echo "session.sh: unknown option '$1'" >&2; exit 2 ;;
    *)
        [ -z "$DIR" ] || { echo "session.sh: usage: sh bench/session.sh DIR [--quick]" >&2; exit 2; }
        DIR=$1; shift ;;
    esac
done
[ -n "$DIR" ] || { echo "session.sh: usage: sh bench/session.sh DIR [--quick]" >&2; exit 2; }

if [ -z "$QUICK" ] && [ -e "$DIR" ]; then
    [ -d "$DIR" ] || { echo "session.sh: '$DIR' exists and is not a directory" >&2; exit 2; }
    if [ -n "$(ls -A "$DIR")" ]; then
        echo "session.sh: '$DIR' is not empty (a final-mode session needs an empty directory)" >&2
        exit 2
    fi
fi
if [ -n "$QUICK" ] && [ -f "$DIR/session.txt" ]; then
    case $(head -1 "$DIR/session.txt") in
    quick-*) ;;
    *) echo "session.sh: '$DIR/session.txt' records a final session; refusing to overwrite a final session" >&2; exit 2 ;;
    esac
fi
mkdir -p "$DIR" || { echo "session.sh: cannot create '$DIR'" >&2; exit 2; }

HEX=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
case $HEX in
[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
*) echo "session.sh: cannot read 4 random bytes from /dev/urandom" >&2; exit 2 ;;
esac
ID="$(date -u +%Y%m%dT%H%M%SZ)-$HEX"
[ -n "$QUICK" ] && ID="quick-$ID"
printf '%s\n' "$ID" >"$DIR/session.txt.tmp" && mv -f "$DIR/session.txt.tmp" "$DIR/session.txt" \
    || { rm -f "$DIR/session.txt.tmp"; echo "session.sh: cannot write '$DIR/session.txt'" >&2; exit 2; }
echo "session $ID in $DIR"
exit 0
