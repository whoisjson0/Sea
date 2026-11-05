#!/bin/sh
# bench/workloads/run.sh -- the timed runs of the workload benchmark (DESIGN.md 6.5, 2.17.4).
# POSIX sh. Run by bench/workloads.sh on the Mac and, from the unpacked bundle, by its remote
# script on the Linux host.
#
# usage: sh run.sh [--quick] [-c COMPILE_TSV] TARGET SPAWN BIN FIX W NAME...
#   TARGET   arm64-macos (variant neon, SEA_KERNELS unset) or x86_64-linux (variants avx2 and
#            sse2, SEA_KERNELS set to each)
#   SPAWN    the built helper spawn_time (absolute path)
#   BIN      the built ports BIN/NAME
#   FIX      the per-port fixture directories FIX/NAME/ (each may be empty)
#   W        an empty work directory (absolute path)
#   NAME...  the workloads, in the order to run (W1, W2, W3, W4, W5, W7, W8)
#   --quick  1 + 1 runs (run 1 and one further run) instead of 5 + 10
#   -c FILE  the compile times `NAME<TAB>wall` (bench/workloads.sh build); without it the
#            summary's compile_s column is empty (Linux)
#
# For each NAME and each variant: 15 consecutive runs (quick: 2) with nothing between them but
# their setup. Run K creates W/VARIANT/NAME/rK/, copies FIX/NAME/* into it, then runs
#     SPAWN W/VARIANT/NAME/rK W/VARIANT/NAME/rK.out W/VARIANT/NAME/rK.err -- BIN/NAME --export-reference
# After the runs of a workload and variant, every run is checked (L-oy): status 0; rK.err empty;
# exactly one `Compute time` line, of the form `^Compute time: [0-9]+\.[0-9]{3} s$`; the run
# directory holds exactly NAME.json and the fixtures, each byte-identical to FIX/NAME/; runs 2..
# equal run 1 (NAME.json byte for byte, standard output byte for byte without the Compute time
# line). Run 1's correctness against the references is judged by the Mac driver, not here.
#
# Environment of the measured processes (2.17.3): SEA_HEAP_CHECK, BAYSICK_KERNELS,
# VECLIB_MAXIMUM_THREADS, OPENBLAS_NUM_THREADS and OMP_NUM_THREADS removed; SEA_KERNELS removed on
# the Mac and set to the variant on Linux; LC_ALL, which this script sets to C for its own
# processing, removed (C4); standard input /dev/null (spawn_time).
#
# Writes into W: runs.tsv (header `target variant workload run wall_s cpu_s compute_s status`),
# summary.tsv (the header of workloads-<target>.tsv, 2.17.9), load_after (the three load averages
# read just after the last measured process) and keeps every run directory and output.
# Progress goes to standard error.
# Exit status: 0 measured and checked, 1 a validation failure (named on standard error), 2 setup
# error.

LC_ALL=C; export LC_ALL
QUICK=
CTSV=
while [ $# -gt 0 ]; do
    case $1 in
    --quick) QUICK=1; shift ;;
    -c) [ $# -ge 2 ] || { echo "run.sh: missing argument for '-c'" >&2; exit 2; }; CTSV=$2; shift 2 ;;
    -*) echo "run.sh: unknown option '$1'" >&2; exit 2 ;;
    *) break ;;
    esac
done
[ $# -ge 6 ] || { echo "run.sh: usage: sh run.sh [--quick] [-c COMPILE_TSV] TARGET SPAWN BIN FIX W NAME..." >&2; exit 2; }
TARGET=$1; SPAWN=$2; BIN=$3; FIX=$4; W=$5; shift 5
NAMES="$*"

case $TARGET in
arm64-macos) VARIANTS=neon ;;
x86_64-linux) VARIANTS="avx2 sse2" ;;
*) echo "run.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac
if [ -n "$QUICK" ]; then NRUNS=2; NPASS=1; else NRUNS=15; NPASS=5; fi
[ -x "$SPAWN" ] || { echo "run.sh: helper '$SPAWN' not found" >&2; exit 2; }
[ -d "$W" ] || { echo "run.sh: work directory '$W' not found" >&2; exit 2; }
for nm in $NAMES; do
    [ -x "$BIN/$nm" ] || { echo "run.sh: port '$BIN/$nm' not built" >&2; exit 2; }
    [ -d "$FIX/$nm" ] || { echo "run.sh: fixture directory '$FIX/$nm' missing" >&2; exit 2; }
    if [ -n "$CTSV" ] && ! awk -F '\t' -v n="$nm" '$1 == n { f = 1 } END { exit !f }' "$CTSV"; then
        echo "run.sh: no compile time of $nm in '$CTSV'" >&2; exit 2
    fi
done

if [ "$(uname -s)" = Darwin ]; then
    CPU=$(sysctl -n machdep.cpu.brand_string)
else
    CPU=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -1)
fi
[ -n "$CPU" ] || CPU=-

unset SEA_HEAP_CHECK BAYSICK_KERNELS VECLIB_MAXIMUM_THREADS OPENBLAS_NUM_THREADS OMP_NUM_THREADS SEA_KERNELS

loads() {
    uptime | sed -n 's/.*load average[s]*: *//p' | tr -d ',' | awk 'NF == 3 { print $1, $2, $3 }'
}

CRE='^Compute time: [0-9]+\.[0-9]{3} s$'
printf 'target\tvariant\tworkload\trun\twall_s\tcpu_s\tcompute_s\tstatus\n' >"$W/runs.tsv"
printf 'target\tcpu\tvariant\tworkload\tcompile_s\tfirst_wall_s\tbest5_wall_s\tmedian5_wall_s\tmedian10_wall_s\tmin10_wall_s\tmax10_wall_s\tfirst_compute_s\tbest5_compute_s\tmedian5_compute_s\tmedian10_compute_s\tmin10_compute_s\tmax10_compute_s\n' >"$W/summary.tsv"

# vfail VARIANT NAME RUN CHECK : a validation failure
vfail() {
    echo "run.sh: validation failure: $2 ($1) run $3: $4" >&2
    exit 1
}

LASTNM=; for nm in $NAMES; do LASTNM=$nm; done
LASTV=; for v in $VARIANTS; do LASTV=$v; done

for nm in $NAMES; do
    for v in $VARIANTS; do
        if [ "$TARGET" = x86_64-linux ]; then SEA_KERNELS=$v; export SEA_KERNELS; fi
        D=$W/$v/$nm
        mkdir -p "$D" || exit 2
        echo "run.sh: $nm ($v): $NRUNS runs" >&2
        # ---- the timed runs: nothing between them but their setup
        k=1
        while [ $k -le $NRUNS ]; do
            mkdir "$D/r$k" || exit 2
            for f in "$FIX/$nm"/*; do
                [ -e "$f" ] || continue
                cp "$f" "$D/r$k/" || { echo "run.sh: cannot copy fixture $f" >&2; exit 2; }
            done
            (unset LC_ALL; exec "$SPAWN" "$D/r$k" "$D/r$k.out" "$D/r$k.err" -- "$BIN/$nm" --export-reference) >"$D/r$k.spawn" \
                || { echo "run.sh: spawn_time failed for $nm ($v) run $k" >&2; exit 2; }
            k=$((k + 1))
        done
        unset SEA_KERNELS
        if [ "$nm" = "$LASTNM" ] && [ "$v" = "$LASTV" ]; then
            loads >"$W/load_after"
        fi
        # ---- the checks of every run (L-oy)
        ls "$FIX/$nm" | sort >"$D/allowed"
        printf '%s\n' "$nm.json" >>"$D/allowed"
        sort -o "$D/allowed" "$D/allowed"
        k=1
        while [ $k -le $NRUNS ]; do
            line=$(cat "$D/r$k.spawn")
            echo "$line" | grep -Eqx 'wall [0-9]+\.[0-9]{9} cpu [0-9]+\.[0-9]{9} status [0-9]+' \
                || { echo "run.sh: malformed spawn_time line '$line' ($nm, $v, run $k)" >&2; exit 2; }
            set -- $line
            wall=$2; cpu=$4; st=$6
            [ "$st" = 0 ] || vfail "$v" "$nm" "$k" "exit status $st, expected 0"
            [ -s "$D/r$k.err" ] && vfail "$v" "$nm" "$k" "standard error not empty: $(head -2 "$D/r$k.err" | tr '\n' ' ')"
            nct=$(grep -c '^Compute time' "$D/r$k.out")
            [ "$nct" = 1 ] || vfail "$v" "$nm" "$k" "$nct 'Compute time' lines, expected exactly one"
            cline=$(grep -E "$CRE" "$D/r$k.out")
            [ -n "$cline" ] || vfail "$v" "$nm" "$k" "malformed 'Compute time' line '$(grep '^Compute time' "$D/r$k.out")'"
            ct=$(echo "$cline" | sed 's/^Compute time: \([0-9.]*\) s$/\1/')
            (cd "$D/r$k" && find . -mindepth 1 | sed 's|^\./||' | sort) >"$D/r$k.files"
            cmp -s "$D/r$k.files" "$D/allowed" \
                || vfail "$v" "$nm" "$k" "the run directory holds '$(tr '\n' ' ' <"$D/r$k.files")', expected exactly '$(tr '\n' ' ' <"$D/allowed")'"
            [ -f "$D/r$k/$nm.json" ] || vfail "$v" "$nm" "$k" "$nm.json is not a regular file"
            for f in "$FIX/$nm"/*; do
                [ -e "$f" ] || continue
                b=${f##*/}
                [ -f "$D/r$k/$b" ] && cmp -s "$f" "$D/r$k/$b" || vfail "$v" "$nm" "$k" "fixture $b changed"
            done
            grep -Ev "$CRE" "$D/r$k.out" >"$D/r$k.cmpout"
            if [ $k -gt 1 ]; then
                cmp -s "$D/r1/$nm.json" "$D/r$k/$nm.json" || vfail "$v" "$nm" "$k" "$nm.json differs from run 1"
                cmp -s "$D/r1.cmpout" "$D/r$k.cmpout" || vfail "$v" "$nm" "$k" "standard output differs from run 1 (Compute time line aside)"
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TARGET" "$v" "$nm" "$k" "$wall" "$cpu" "$ct" "$st" >>"$W/runs.tsv"
            k=$((k + 1))
        done
        # ---- the summary row, exactly in decimal (2.17.4 "What is computed")
        comp=
        if [ -n "$CTSV" ]; then
            comp=$(awk -F '\t' -v n="$nm" '$1 == n { printf "%.3f", $2; exit }' "$CTSV")
        fi
        awk -F '\t' -v tg="$TARGET" -v cpu="$CPU" -v vr="$v" -v nm="$nm" -v comp="$comp" -v np="$NPASS" '
        # scaled d s : the decimal string s with exactly d decimals as an integer
        function scaled(d, s,   p) {
            p = index(s, ".")
            if (p == 0 || length(s) - p != d) { print "run.sh: bad decimal " s > "/dev/stderr"; bad = 1; exit 2 }
            return substr(s, 1, p - 1) * 10 ^ d + substr(s, p + 1)
        }
        # fmt d x : the integer x as a decimal with d decimals
        function fmt(d, x,   ip) {
            ip = int(x / 10 ^ d)
            return sprintf("%d.%0" d "d", ip, x - ip * 10 ^ d)
        }
        # sortv n : sort a[1..n] ascending (insertion sort; n <= 15)
        function sortv(n,   i, j, t) {
            for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
        }
        # stats d col : first, best and median of the pass set, median of the further set (one
        # decimal more: the exact mean of its two middle values), its minimum and maximum
        function stats(d, col,   i, n, s, q, out) {
            out = fmt(d, v[col, 1])
            n = 0; for (i = 1; i <= np; i++) a[++n] = v[col, i]
            sortv(n)
            out = out "\t" fmt(d, a[1]) "\t" fmt(d, a[int((n + 1) / 2)])
            n = 0; for (i = np + 1; i <= nr; i++) a[++n] = v[col, i]
            sortv(n)
            s = a[int((n + 1) / 2)] + a[int(n / 2) + 1]
            q = int(s / 2)
            out = out "\t" fmt(d, q) ((s - 2 * q) ? "5" : "0") "\t" fmt(d, a[1]) "\t" fmt(d, a[n])
            return out
        }
        NR > 1 && $2 == vr && $3 == nm { nr++; v[1, nr] = scaled(9, $5); v[2, nr] = scaled(3, $7) }
        END {
            if (bad) exit 2
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", tg, cpu, vr, nm, comp, stats(9, 1), stats(3, 2)
        }' "$W/runs.tsv" >>"$W/summary.tsv" || { echo "run.sh: computing the summary of $nm ($v) failed" >&2; exit 2; }
    done
done
exit 0
