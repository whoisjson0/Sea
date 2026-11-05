"""bench/numpy_time.py -- the NumPy column of the workload benchmark (DESIGN.md 2.17.5, Decision 167).

Usage (run by bench/numpy.sh, never directly in a measurement):
    uv run --no-project --with numpy==2.5.4 python -I bench/numpy_time.py [--quick] DIR SCRATCH

Puts workloads/reference_py first on sys.path and imports numpy, common and compare; writes
SCRATCH/info.txt (`key<TAB>value` lines: tools, numpy_blas, numpy_threads, and after the last
timed run load_after). For each workload W1, W2, W3, W4, W5, W7, W8 it imports the module
(untimed) and makes 5 runs in this process (--quick: 1). Before run K, outside the timed region,
common.REF_DIR is set to the fresh directory SCRATCH/NAME/rK (so the committed
reference/<name>.py.json is never written), standard output is flushed and file descriptor 1 is
pointed at SCRATCH/NAME/rK.out. The timed region is
    t0 = time.perf_counter(); mod.main(); sys.stdout.flush(); t = time.perf_counter() - t0
after which file descriptor 1 is restored. After the last run of the last workload, run 1 of each
workload is checked with compare.compare(NAME, <reference>/NAME.json, SCRATCH/NAME/r1/NAME.py.json,
candidate=False, quiet=True) returning an empty list, and runs 2-5's NAME.py.json must be
byte-identical to run 1's. Then SCRATCH/numpy-arm64-macos.tsv is written (header
`target cpu workload numpy python reps first_s median5_s best5_s`, times %.9f); bench/numpy.sh
publishes it into DIR (which must exist) with the machine record, only when this script succeeded
(review finding 9).

Exit status: 0 measured, validated and written; 1 a validation failure (no file written);
2 a setup error.
"""

import importlib
import os
import platform
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFPY = os.path.join(ROOT, "workloads", "reference_py")
NAMES = ["w1_shaft_design", "w2_truss_fem", "w3_quarter_car", "w4_heat_plate",
         "w5_tolerance_mc", "w7_drivetrain", "w8_ev_can"]
TARGET = "arm64-macos"
HEADER = "target\tcpu\tworkload\tnumpy\tpython\treps\tfirst_s\tmedian5_s\tbest5_s\n"


def say(text):
    """Progress on standard error (file descriptor 1 is redirected during the runs)."""
    sys.stderr.write("numpy_time.py: %s\n" % text)
    sys.stderr.flush()


def setup_error(text):
    say(text)
    sys.exit(2)


def main(argv):
    quick = False
    if argv and argv[0] == "--quick":
        quick = True
        argv = argv[1:]
    if len(argv) != 2:
        setup_error("usage: numpy_time.py [--quick] DIR SCRATCH")
    out_dir, scratch = (os.path.abspath(a) for a in argv)
    if not os.path.isdir(out_dir):
        setup_error("results directory %s not found" % out_dir)
    if not os.path.isdir(scratch):
        setup_error("scratch directory %s not found" % scratch)
    reps = 1 if quick else 5

    sys.path.insert(0, REFPY)
    import numpy
    import common
    import compare

    blas = numpy.show_config(mode="dicts").get("Build Dependencies", {}).get("blas")
    if blas:
        numpy_blas = "%s %s" % (blas.get("name", "-"), blas.get("version", "-"))
    else:
        numpy_blas = "-"
    threads = " ".join("%s=%s" % (v, os.environ.get(v, "unset"))
                       for v in ("VECLIB_MAXIMUM_THREADS", "OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS"))
    info_path = os.path.join(scratch, "info.txt")
    with open(info_path, "w") as fh:
        fh.write("tools\tnumpy %s, Python %s\n" % (numpy.__version__, platform.python_version()))
        fh.write("numpy_blas\t%s\n" % numpy_blas)
        fh.write("numpy_threads\t%s\n" % threads)
    cpu = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                         text=True).stdout.strip() or "-"

    times = {}
    for name in NAMES:
        mod = importlib.import_module(name)
        say("%s: %d run%s" % (name, reps, "" if reps == 1 else "s"))
        times[name] = []
        for k in range(1, reps + 1):
            run_dir = os.path.join(scratch, name, "r%d" % k)
            os.makedirs(run_dir)
            common.REF_DIR = run_dir
            sys.stdout.flush()
            saved = os.dup(1)
            fd = os.open(os.path.join(scratch, name, "r%d.out" % k),
                         os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
            os.dup2(fd, 1)
            os.close(fd)
            try:
                t0 = time.perf_counter()
                mod.main()
                sys.stdout.flush()
                t = time.perf_counter() - t0
            finally:
                os.dup2(saved, 1)
                os.close(saved)
            times[name].append(t)

    with open(info_path, "a") as fh:
        fh.write("load_after\t%.2f %.2f %.2f\n" % os.getloadavg())

    for name in NAMES:
        first = os.path.join(scratch, name, "r1", name + ".py.json")
        if not os.path.isfile(first):
            say("validation failure: %s run 1 wrote no %s.py.json" % (name, name))
            return 1
        failed = compare.compare(name, os.path.join(compare.REF_DIR, name + ".json"), first,
                                 candidate=False, quiet=True)
        if failed:
            say("validation failure: %s run 1: compare.py's NumPy mode fails the keys %s"
                % (name, ", ".join(failed)))
            return 1
        with open(first, "rb") as fh:
            want = fh.read()
        for k in range(2, reps + 1):
            path = os.path.join(scratch, name, "r%d" % k, name + ".py.json")
            got = None
            if os.path.isfile(path):
                with open(path, "rb") as fh:
                    got = fh.read()
            if got != want:
                say("validation failure: %s run %d: %s.py.json differs from run 1" % (name, k, name))
                return 1

    rows = [HEADER]
    for name in NAMES:
        t = times[name]
        s = sorted(t)
        rows.append("%s\t%s\t%s\t%s\t%s\t%d\t%.9f\t%.9f\t%.9f\n"
                    % (TARGET, cpu, name, numpy.__version__, platform.python_version(), reps,
                       t[0], s[(len(s) - 1) // 2], s[0]))
    path = os.path.join(scratch, "numpy-%s.tsv" % TARGET)
    with open(path, "w") as fh:
        fh.writelines(rows)
    say("wrote %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
