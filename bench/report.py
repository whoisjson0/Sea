#!/usr/bin/env python3
# report.py -- the generated sections of docs/BENCH.md (docs/DESIGN.md section 2.17.9, L-pn).
#
# Purpose:  print, from the result files of DIR and the MATLAB baseline files, the Markdown of
#           BENCH.md section 2 (machines) and sections 4-8 (workloads, pass check, kernels,
#           micro-benchmarks, Linux), or with --readme the short table of Decision 169 (a).
#           Every number is formatted from a file; none is typed by hand.
# Usage:    uv run --no-project python -I bench/report.py DIR
#           uv run --no-project python -I bench/report.py --readme DIR
# Input:    DIR/session.txt, env-*.txt, workloads-runs-*.tsv, workloads-*.tsv,
#           numpy-arm64-macos.tsv, kernels-*.tsv, micro-*.tsv, check.txt (each optional except
#           the Mac workload files; a missing optional file is stated in its section), and
#           workloads/reference/baseline_timings_matlab*.json.
# Output:   Markdown on standard output. Times and walls to 3 decimals, ratios to 2 decimals,
#           rates as %.2f.
# Exit:     0 printed; 2 a missing or malformed required file (one line "report: <reason>").
# Library:  the Python standard library only (L-pq).

import json
import os
import sys
from decimal import Decimal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFDIR = os.path.join(ROOT, "workloads", "reference")
DEFAULT_DIR = os.path.join(ROOT, "bench", "results", "p10")

MAC = "arm64-macos"
LINUX = "x86_64-linux"
WORKLOADS = [
    "w1_shaft_design", "w2_truss_fem", "w3_quarter_car", "w4_heat_plate",
    "w5_tolerance_mc", "w7_drivetrain", "w8_ev_can",
]
TOOLS = ["workloads", "kernels", "micro", "numpy"]
RUNS_HEADER = "target variant workload run wall_s cpu_s compute_s status".split()
SUMMARY_HEADER = (
    "target cpu variant workload compile_s first_wall_s best5_wall_s median5_wall_s "
    "median10_wall_s min10_wall_s max10_wall_s first_compute_s best5_compute_s "
    "median5_compute_s median10_compute_s min10_compute_s max10_compute_s"
).split()
NUMPY_HEADER = "target cpu workload numpy python reps first_s median5_s best5_s".split()
KERNELS_HEADER = ("target cpu kernel impl variant n reps batch median_s min_s max_s unit rate "
                  "pct_vendor").split()
MICRO_HEADER = "target cpu bench compiler reps median_s min_s max_s unit rate".split()


class ReportError(Exception):
    pass


def fail(msg):
    raise ReportError(msg)


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", newline="") as f:
            return f.read()
    except OSError as e:
        fail("cannot read %s: %s" % (path, e.strerror or e))
    except UnicodeDecodeError:
        fail("%s is not UTF-8 text" % path)


def read_env(path):
    env = {}
    text = read_text(path)
    for line in text.split("\n")[:-1] if text.endswith("\n") else text.split("\n"):
        if not line:
            continue
        if "\t" not in line:
            fail("malformed %s" % path)
        k, v = line.split("\t", 1)
        env[k] = v
    return env


def read_tsv(path, header):
    text = read_text(path)
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines or lines[0].split("\t") != header:
        fail("%s: unexpected header row" % path)
    rows = []
    for n, line in enumerate(lines[1:], 2):
        f = line.split("\t")
        if len(f) != len(header):
            fail("%s line %d: %d fields, expected %d" % (path, n, len(f), len(header)))
        rows.append(dict(zip(header, f)))
    return rows


def exists(dirpath, name):
    return os.path.isfile(os.path.join(dirpath, name))


def num(s, path=""):
    try:
        return float(s)
    except ValueError:
        fail("%s: '%s' is not a number" % (path, s))


def f3(x):
    return "%.3f" % x


def f2(x):
    return "%.2f" % x


def esc(s):
    return s.replace("|", "\\|")


def table(head, rows, align=None):
    """Markdown table; align: string of l/r per column (default: first l, rest r)."""
    if align is None:
        align = "l" + "r" * (len(head) - 1)
    out = ["| " + " | ".join(esc(h) for h in head) + " |",
           "|" + "|".join(":---" if a == "l" else "---:" for a in align) + "|"]
    for r in rows:
        out.append("| " + " | ".join(esc(c) for c in r) + " |")
    return out


# ---------------------------------------------------------------------------------------
# MATLAB baseline
# ---------------------------------------------------------------------------------------

def read_matlab_file(fname):
    path = os.path.join(REFDIR, fname)
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except OSError as e:
        fail("cannot read %s: %s" % (path, e.strerror or e))
    except ValueError:
        fail("malformed %s" % path)


def matlab_values(fname):
    """-> {workload: dict(first_total, median_total, best_total, first_comp, median_comp,
    best_comp)} for one MATLAB file (lists indexed by 'workloads', or scalars + flat lists)."""
    d = read_matlab_file(fname)
    names = d.get("workloads")
    if not isinstance(names, list):
        fail("%s: no 'workloads' list" % fname)
    out = {}
    try:
        for i, name in enumerate(names):
            if isinstance(d["total_seconds_best"], list):
                tot, com = d["total_seconds"][i], d["compute_seconds"][i]
                tm, cm = d["total_seconds_median"][i], d["compute_seconds_median"][i]
                tb, cb = d["total_seconds_best"][i], d["compute_seconds_best"][i]
            else:
                tot, com = d["total_seconds"], d["compute_seconds"]
                tm, cm = d["total_seconds_median"], d["compute_seconds_median"]
                tb, cb = d["total_seconds_best"], d["compute_seconds_best"]
            out[name] = {"ft": tot[0], "mt": tm, "bt": tb, "fc": com[0], "mc": cm, "bc": cb}
    except (KeyError, IndexError, TypeError):
        fail("%s: unexpected structure" % fname)
    return out


def matlab_default():
    m = {}
    for fn in ("baseline_timings_matlab.json", "baseline_timings_matlab_w7_drivetrain.json",
               "baseline_timings_matlab_w8_ev_can.json"):
        m.update(matlab_values(fn))
    for n in WORKLOADS:
        if n not in m:
            fail("no MATLAB baseline for %s" % n)
    return m


# ---------------------------------------------------------------------------------------
# Loading the result directory
# ---------------------------------------------------------------------------------------

class Data:
    def __init__(self, dirpath):
        self.dir = dirpath
        self.session = read_text(os.path.join(dirpath, "session.txt")).strip()
        self.env = {}  # (tool, target) -> dict
        try:
            names = sorted(os.listdir(dirpath))
        except OSError as e:
            fail("cannot read %s: %s" % (dirpath, e.strerror or e))
        for fn in names:
            if fn.startswith("env-") and fn.endswith(".txt"):
                stem = fn[4:-4]
                for t in TOOLS:
                    if stem.startswith(t + "-"):
                        self.env[(t, stem[len(t) + 1:])] = read_env(os.path.join(dirpath, fn))
        self.summary = {}   # target -> rows
        self.runs = {}      # target -> rows
        self.kernels = {}
        self.micro = {}
        for tgt in (MAC, LINUX):
            for store, prefix, hdr in ((self.summary, "workloads-", SUMMARY_HEADER),
                                       (self.runs, "workloads-runs-", RUNS_HEADER),
                                       (self.kernels, "kernels-", KERNELS_HEADER),
                                       (self.micro, "micro-", MICRO_HEADER)):
                fn = "%s%s.tsv" % (prefix, tgt)
                if exists(dirpath, fn):
                    store[tgt] = read_tsv(os.path.join(dirpath, fn), hdr)
        self.numpy = None
        if exists(dirpath, "numpy-%s.tsv" % MAC):
            self.numpy = read_tsv(os.path.join(dirpath, "numpy-%s.tsv" % MAC), NUMPY_HEADER)
        self.check = None
        if exists(dirpath, "check.txt"):
            self.check = read_text(os.path.join(dirpath, "check.txt"))


def mac_summary(data):
    if MAC not in data.summary:
        fail("workloads-%s.tsv is missing in %s" % (MAC, data.dir))
    by = {}
    for r in data.summary[MAC]:
        by[r["workload"]] = r
    for n in WORKLOADS:
        if n not in by:
            fail("workloads-%s.tsv lacks %s" % (MAC, n))
    return by


# ---------------------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------------------

def sec_machines(data):
    out = ["## 2. Machines", "", "Session: `%s`" % data.session, ""]
    targets = [t for t in (MAC, LINUX) if any(k[1] == t for k in data.env)]
    if not targets:
        out += ["No `env-*.txt` record in the directory.", ""]
    for tgt in targets:
        recs = {tool: data.env[(tool, tgt)] for tool in TOOLS if (tool, tgt) in data.env}
        first = recs.get("workloads") or next(iter(recs.values()))
        out += ["### %s" % tgt, ""]
        keys = ["machine_model", "cpu", "os", "sea_commit", "sea_dirty", "baysick_commit",
                "baysick_dirty", "power", "lowpower"]
        out += table(["Item", "Value"],
                     [[k, "`%s`" % first.get(k, "-")] for k in keys], "ll")
        out += [""]
        rows = []
        for tool in TOOLS:
            if tool in recs:
                e = recs[tool]
                rows.append([tool, e.get("mode", "-"), e.get("date", "-"), e.get("nice", "-"),
                             e.get("variants", "-"), e.get("tools", "-"),
                             e.get("settle_waited_s", "-"), e.get("load_before", "-"),
                             e.get("load_after", "-")])
        out += table(["Tool", "Mode", "Date (UTC)", "Nice", "Variants", "Compilers / versions",
                      "Start-condition wait (s)", "Load before", "Load after"], rows,
                     "lllllllll")
        out += [""]
        if "numpy" in recs:
            e = recs["numpy"]
            out += ["NumPy: BLAS `%s`; thread variables (VECLIB_MAXIMUM_THREADS, "
                    "OPENBLAS_NUM_THREADS, OMP_NUM_THREADS) `%s`." % (
                        e.get("numpy_blas", "-"), e.get("numpy_threads", "-")), ""]
    return out


def wall_row(r, kind):
    """first, best5, median5, median10 [min-max] of one summary row, as strings."""
    f = lambda c: f3(num(r[c]))
    return [f("first_%s_s" % kind), f("best5_%s_s" % kind), f("median5_%s_s" % kind),
            "%s [%s–%s]" % (f("median10_%s_s" % kind), f("min10_%s_s" % kind),
                                 f("max10_%s_s" % kind))]


def sec_workloads(data):
    summ = mac_summary(data)
    ml = matlab_default()
    out = ["## 4. Workloads against MATLAB", ""]
    for kind, label, mf, mm, mb, key in (
            ("wall", "Whole-process time (s)", "ft", "mt", "bt", "total"),
            ("compute", "Compute time (s)", "fc", "mc", "bc", "compute")):
        out += ["### %s" % label, "",
                "Sea on `%s` (variant `neon`); MATLAB `%s_seconds` of the default-threads files "
                "(in-session times). The ratio is MATLAB's best divided by Sea's best of 5." % (
                    MAC, key), ""]
        rows = []
        for n in WORKLOADS:
            r = summ[n]
            m = ml[n]
            ratio = float(m[mb]) / num(r["best5_%s_s" % kind])
            rows.append([n] + wall_row(r, kind) + [f3(float(m[mf])), f3(float(m[mm])),
                                                    f3(float(m[mb])), f2(ratio)])
        out += table(["Workload", "Sea first", "Sea best of 5", "Sea median of 5",
                      "Sea median of 10 [min–max]", "MATLAB first", "MATLAB median",
                      "MATLAB best", "MATLAB best / Sea best (×)"], rows)
        out += [""]

    one = matlab_values("baseline_timings_matlab_1thread.json")
    out += ["### Single-threaded MATLAB (W1–W5), reported", "",
            "MATLAB with one computational thread (`baseline_timings_matlab_1thread.json`), "
            "beside Sea's best of 5. Ratios are MATLAB's best divided by Sea's best.", ""]
    rows = []
    for n in WORKLOADS[:5]:
        if n not in one:
            fail("the 1-thread MATLAB file lacks %s" % n)
        r, m = summ[n], one[n]
        rows.append([n, f3(float(m["bt"])), f3(num(r["best5_wall_s"])),
                     f2(float(m["bt"]) / num(r["best5_wall_s"])),
                     f3(float(m["bc"])), f3(num(r["best5_compute_s"])),
                     f2(float(m["bc"]) / num(r["best5_compute_s"]))])
    out += table(["Workload", "MATLAB 1 thread best total", "Sea best wall", "total ratio (×)",
                  "MATLAB 1 thread best compute", "Sea best compute", "compute ratio (×)"],
                 rows)
    out += [""]

    out += ["### NumPy, reported (never judged)", ""]
    if data.numpy is None:
        out += ["`numpy-%s.tsv` is not present in this directory." % MAC, ""]
    else:
        by = {r["workload"]: r for r in data.numpy}
        rows = []
        for n in WORKLOADS:
            if n not in by:
                fail("numpy-%s.tsv lacks %s" % (MAC, n))
            r = by[n]
            rows.append([n, f3(num(r["first_s"])), f3(num(r["median5_s"])),
                         f3(num(r["best5_s"])),
                         f2(num(r["best5_s"]) / float(ml[n]["bt"]))])
        v = data.numpy[0]
        out += ["NumPy %s, Python %s, %s in one process. The time is the in-process "
                "time of the script's whole `main()` with NumPy's default threads; the ratio "
                "is NumPy's best divided by MATLAB's best `total_seconds` (both in-session "
                "times), never by Sea's whole-process time." % (
                    v["numpy"], v["python"],
                    "1 repetition" if v["reps"] == "1" else "%s repetitions" % v["reps"]), ""]
        out += table(["Workload", "NumPy first (s)", "NumPy median of 5 (s)",
                      "NumPy best of 5 (s)", "NumPy best / MATLAB best (×)"], rows)
        out += [""]

    out += ["### Runs that waited for a CPU", "",
            "A run is flagged when its user + system CPU time is below 0.8 × its wall "
            "time (DESIGN.md section 2.17.3).", ""]
    flagged = []
    for tgt in (MAC, LINUX):
        for r in data.runs.get(tgt, []):
            wall, cpu = Decimal(r["wall_s"]), Decimal(r["cpu_s"])
            if cpu < Decimal("0.8") * wall:
                flagged.append([r["target"], r["variant"], r["workload"], r["run"],
                                f3(float(wall)), f3(float(cpu))])
    if flagged:
        out += table(["Target", "Variant", "Workload", "Run", "Wall (s)", "CPU (s)"], flagged,
                     "lllrrr")
    else:
        out += ["No run flagged."]
    out += [""]

    out += ["### Compile times (reported, never counted)", ""]
    out += table(["Workload", "Compile time (s)"],
                 [[n, f3(num(summ[n]["compile_s"]))] for n in WORKLOADS])
    out += [""]
    return out


def sec_check(data):
    out = ["## 5. The pass check", ""]
    if data.check is None:
        out += ["`check.txt` is not present in this directory (the pass check gave no verdict).",
                ""]
    else:
        out += ["```", data.check.rstrip("\n"), "```", ""]
    return out


def sec_kernels(data):
    out = ["## 6. Sea-level kernels", ""]
    if not data.kernels:
        return out + ["No `kernels-*.tsv` is present in this directory.", ""]
    for tgt in (MAC, LINUX):
        rows = data.kernels.get(tgt)
        if rows is None:
            continue
        cpu = rows[0]["cpu"] if rows else "-"
        out += ["### %s (%s)" % (tgt, cpu), ""]
        kernels = []
        for r in rows:
            if r["kernel"] not in kernels:
                kernels.append(r["kernel"])
        for k in kernels:
            kr = [r for r in rows if r["kernel"] == k]
            unit = kr[0]["unit"]
            variants = []
            for r in kr:
                if r["impl"] == "sea" and r["variant"] not in variants:
                    variants.append(r["variant"])
            others = []
            for r in kr:
                if r["impl"] != "sea" and r["impl"] not in others:
                    others.append(r["impl"])
            sizes = []
            for r in kr:
                if r["n"] not in sizes:
                    sizes.append(r["n"])
            sizes.sort(key=int)
            head = ["N"] + ["sea %s (%s)" % (v, unit) for v in variants] + \
                   ["%s (%s)" % (o, unit) for o in others] + \
                   ["%% vendor, sea %s" % v for v in variants]
            body = []
            for n in sizes:
                line = [n]
                cell = {(r["impl"], r["variant"]): r for r in kr if r["n"] == n}
                for v in variants:
                    r = cell.get(("sea", v))
                    line.append(f2(num(r["rate"])) if r else "")
                for o in others:
                    rs = [r for (i, _), r in cell.items() if i == o]
                    line.append(f2(num(rs[0]["rate"])) if rs else "")
                for v in variants:
                    r = cell.get(("sea", v))
                    line.append(r["pct_vendor"] if r else "")
                body.append(line)
            out += ["#### %s" % k, ""] + table(head, body) + [""]
    return out


def sec_micro(data):
    out = ["## 7. Micro-benchmarks", "",
           "Measured with the current compiler (DESIGN.md section 2.17.7). The phase-5 "
           "measurement is the table of DESIGN.md section 5.9 (`bench/results/micro-*.tsv`).",
           ""]
    if not data.micro:
        return out + ["No `micro-*.tsv` is present in this directory.", ""]
    for tgt in (MAC, LINUX):
        rows = data.micro.get(tgt)
        if rows is None:
            continue
        out += ["### %s (%s)" % (tgt, rows[0]["cpu"] if rows else "-"), ""]
        cref = {r["bench"]: num(r["rate"]) for r in rows if r["compiler"].startswith("c-")}
        body = []
        for r in rows:
            ratio = ""
            if r["compiler"].startswith("sea") and r["bench"] in cref:
                ratio = f2(num(r["rate"]) / cref[r["bench"]])
            body.append([r["bench"], r["compiler"], r["reps"], f3(num(r["median_s"])),
                         f3(num(r["min_s"])), f3(num(r["max_s"])), r["unit"],
                         f2(num(r["rate"])), ratio])
        out += table(["Bench", "Compiler", "Reps", "Median (s)", "Min (s)", "Max (s)", "Unit",
                      "Rate", "Sea / C"], body, "llrrrrlrr")
        out += [""]
    return out


def sec_linux(data):
    out = ["## 8. Linux x86_64", "",
           "Reported, compared with nothing (Decision 165): no MATLAB baseline exists on this "
           "machine.", ""]
    rows = data.summary.get(LINUX)
    if rows is None:
        return out + ["`workloads-%s.tsv` is not present in this directory." % LINUX, ""]
    variants = []
    for r in rows:
        if r["variant"] not in variants:
            variants.append(r["variant"])
    for kind, label in (("wall", "Whole-process time (s)"), ("compute", "Compute time (s)")):
        for v in variants:
            by = {r["workload"]: r for r in rows if r["variant"] == v}
            body = []
            for n in WORKLOADS:
                if n in by:
                    body.append([n] + wall_row(by[n], kind))
            out += ["### %s, variant `%s`" % (label, v), ""]
            out += table(["Workload", "First", "Best of 5", "Median of 5",
                          "Median of 10 [min–max]"], body)
            out += [""]
    return out


def readme(data):
    summ = mac_summary(data)
    ml = matlab_default()
    env = data.env.get(("workloads", MAC), {})
    rows = []
    for n in WORKLOADS:
        r, m = summ[n], ml[n]
        rows.append([n, f3(num(r["best5_wall_s"])), f3(float(m["bt"])),
                     f3(num(r["best5_compute_s"])), f3(float(m["bc"]))])
    out = table(["Workload", "Sea wall (s)", "MATLAB wall (s)", "Sea compute (s)",
                 "MATLAB compute (s)"], rows)
    out += ["",
            "Best of 5, seconds. Wall is the whole process for Sea and MATLAB's in-session "
            "`total_seconds`; compute is the timed region. Measured on %s (%s), %s, Sea commit "
            "`%s`, session `%s`; see [docs/BENCH.md](docs/BENCH.md)." % (
                env.get("machine_model", "-"), env.get("cpu", "-"), env.get("os", "-"),
                env.get("sea_commit", "-")[:7], data.session)]
    return out


def main(argv):
    mode = "report"
    args = list(argv)
    if args and args[0] == "--readme":
        mode = "readme"
        args = args[1:]
    if len(args) != 1 or args[0].startswith("-"):
        sys.stderr.write("report: usage: report.py [--readme] DIR\n")
        return 2
    try:
        data = Data(args[0])
        if mode == "readme":
            lines = readme(data)
        else:
            lines = []
            for sec in (sec_machines, sec_workloads, sec_check, sec_kernels, sec_micro,
                        sec_linux):
                lines += sec(data)
    except ReportError as e:
        sys.stderr.write("report: %s\n" % e)
        return 2
    sys.stdout.write("\n".join(lines).rstrip("\n") + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
