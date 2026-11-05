#!/bin/sh
# bench/settle.sh -- the start condition before each final-mode measurement (DESIGN.md 2.17.3,
# Decision 170 (a), L-po). POSIX sh; macOS and Linux (run by the drivers and by the cross remote
# scripts on the host). Quick mode never runs it.
#
# usage: sh settle.sh
#
# Sleeps 120 s (the cool-down after the build or the previous tool's measurement), then reads the
# 1-minute load average (uptime) at once and every 10 s after, until it is at most 2.0. The wait
# after the cool-down is counted in those 10-second steps. On success it prints on standard output
# two `key<TAB>value` lines for the machine record:
#     settle_waited_s<TAB>N          (the seconds waited after the cool-down, a multiple of 10)
#     load_before<TAB>L1 L5 L15      (the three load averages of the last reading)
# When the load has not fallen to 2.0 at the reading 15 minutes (900 s) after the end of the
# cool-down, it prints `settle: load average <x> above 2.0 after 15 minutes` on standard error and
# exits 2; the driver then stops with exit 2 without measuring. Progress goes to standard error.
# Exit status: 0 the condition holds, 2 timeout or an unreadable load average.

LC_ALL=C; export LC_ALL
COOL=120
STEP=10
LIMIT=900

# loads : the three load averages of uptime, separated by single spaces (macOS prints
# `load averages: a b c`, Linux `load average: a, b, c`)
loads() {
    uptime | sed -n 's/.*load average[s]*: *//p' | tr -d ',' | awk 'NF == 3 { print $1, $2, $3 }'
}

echo "settle: cool-down of $COOL s" >&2
sleep "$COOL"
waited=0
while :; do
    L=$(loads)
    [ -n "$L" ] || { echo "settle: cannot read the load average from uptime" >&2; exit 2; }
    L1=${L%% *}
    if awk -v l="$L1" 'BEGIN { exit !(l + 0 <= 2.0) }'; then break; fi
    if [ "$waited" -ge "$LIMIT" ]; then
        echo "settle: load average $L1 above 2.0 after 15 minutes" >&2
        exit 2
    fi
    echo "settle: load average $L1 above 2.0 after $waited s; waiting" >&2
    sleep "$STEP"
    waited=$((waited + STEP))
done
echo "settle: load average $L1 after $waited s" >&2
printf 'settle_waited_s\t%s\n' "$waited"
printf 'load_before\t%s\n' "$L"
exit 0
