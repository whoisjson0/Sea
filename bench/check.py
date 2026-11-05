#!/usr/bin/env python3
# check.py -- the pass check of Sea's phase 10 (docs/DESIGN.md section 2.17.8).
#
# Purpose:  decide section 6.5's rule from the committed result files alone: every one of
#           the seven workloads has Sea's best-of-5 whole-process time strictly below
#           MATLAB's best total_seconds AND Sea's best-of-5 printed compute time strictly
#           below MATLAB's best compute_seconds (L-ox, L-pv: the largest value the printed
#           decimals can stand for is compared).
# Usage:    uv run --no-project python -I bench/check.py [DIR]     (DIR default bench/results/p10)
#           uv run --no-project python -I bench/check.py --self-test
# Input:    DIR/session.txt, DIR/workloads-runs-arm64-macos.tsv, DIR/workloads-arm64-macos.tsv,
#           every DIR/env-*.txt, and the four MATLAB files of section 1.2 in workloads/reference/.
# Output:   standard output as in section 2.17.8 (exact text); nothing on standard output on a
#           setup error.
# Exit:     0 PASS, 1 FAIL (a miss or a machine mismatch), 2 setup error (one line
#           "check: <reason>" on standard error).
# Library:  the Python standard library only (L-pq); all arithmetic on measured values is exact
#           (decimal), never floating point.

import json
import os
import re
import sys
from decimal import Decimal

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFDIR = os.path.join(ROOT, "workloads", "reference")
DEFAULT_DIR = os.path.join(ROOT, "bench", "results", "p10")

TARGET = "arm64-macos"
VARIANT = "neon"
WORKLOADS = [
    "w1_shaft_design", "w2_truss_fem", "w3_quarter_car", "w4_heat_plate",
    "w5_tolerance_mc", "w7_drivetrain", "w8_ev_can",
]
MATLAB_FILES = [
    "baseline_timings_matlab.json",
    "baseline_timings_matlab_w7_drivetrain.json",
    "baseline_timings_matlab_w8_ev_can.json",
]
# The 1-thread file is reported only (section 1.2); it is not part of the pass rule, but the
# machine rule (L-pc) is stated for "every MATLAB file", so it is read for the machine too.
MATLAB_MACHINE_FILES = MATLAB_FILES + ["baseline_timings_matlab_1thread.json"]

RUNS_HEADER = "target variant workload run wall_s cpu_s compute_s status".split()
SUMMARY_HEADER = (
    "target cpu variant workload compile_s first_wall_s best5_wall_s median5_wall_s "
    "median10_wall_s min10_wall_s max10_wall_s first_compute_s best5_compute_s "
    "median5_compute_s median10_compute_s min10_compute_s max10_compute_s"
).split()
SUMMARY_CHECKED = SUMMARY_HEADER[5:]

WALL_RE = re.compile(r"^[0-9]+\.[0-9]{9}$")
COMP_RE = re.compile(r"^[0-9]+\.[0-9]{3}$")
WALL_ULP = Decimal("5E-10")   # half of the last printed wall decimal (L-pv)
COMP_ULP = Decimal("0.0005")  # half of the last printed compute decimal (L-ox)
Q10 = Decimal("1E-10")
Q4 = Decimal("1E-4")


class SetupError(Exception):
    """A setup error: the check cannot decide (exit 2)."""


def fail(msg):
    raise SetupError(msg)


# ---------------------------------------------------------------------------------------
# Reading the files
# ---------------------------------------------------------------------------------------

def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", newline="") as f:
            return f.read()
    except OSError as e:
        fail("cannot read %s: %s" % (path, e.strerror or e))
    except UnicodeDecodeError:
        fail("%s is not UTF-8 text" % path)


def read_env(path):
    """key<TAB>value lines -> dict; a duplicate key or a line without a tab is malformed."""
    text = read_text(path)
    if "\r" in text or (text and not text.endswith("\n")):
        fail("malformed %s" % path)
    env = {}
    for line in text.split("\n")[:-1]:
        if "\t" not in line:
            fail("malformed %s: line without a tab" % path)
        k, v = line.split("\t", 1)
        if not k or k in env:
            fail("malformed %s: empty or repeated key '%s'" % (path, k))
        env[k] = v
    return env


def need(env, key, path):
    if key not in env:
        fail("%s lacks '%s'" % (path, key))
    return env[key]


def read_tsv(path, header):
    text = read_text(path)
    if "\r" in text or not text.endswith("\n"):
        fail("malformed %s" % path)
    lines = text.split("\n")[:-1]
    if not lines or lines[0].split("\t") != header:
        fail("%s: unexpected header row" % path)
    rows = []
    for n, line in enumerate(lines[1:], 2):
        f = line.split("\t")
        if len(f) != len(header):
            fail("%s line %d: %d fields, expected %d" % (path, n, len(f), len(header)))
        rows.append(dict(zip(header, f)))
    return rows


def read_matlab(refdir):
    """-> (best, machines): best[name] = (total_best, compute_best) as Decimal; machines is
    the list of (file, machine_model, cpu_brand) of every MATLAB file."""
    best = {}
    machines = []
    for fname in MATLAB_MACHINE_FILES:
        path = os.path.join(refdir, fname)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f, parse_float=Decimal)
        except OSError as e:
            fail("cannot read %s: %s" % (path, e.strerror or e))
        except ValueError:
            fail("malformed %s" % path)
        if not isinstance(data, dict):
            fail("malformed %s" % path)
        for k in ("machine_model", "cpu_brand", "workloads"):
            if k not in data:
                fail("%s lacks '%s'" % (path, k))
        machines.append((fname, data["machine_model"], data["cpu_brand"]))
        if fname not in MATLAB_FILES:
            continue
        names = data["workloads"]
        if not isinstance(names, list) or not names:
            fail("%s: 'workloads' is not a list" % path)
        tb = data.get("total_seconds_best")
        cb = data.get("compute_seconds_best")
        if tb is None or cb is None:
            fail("%s lacks total_seconds_best or compute_seconds_best" % path)
        multi = fname == "baseline_timings_matlab.json"
        if multi:
            if not (isinstance(tb, list) and isinstance(cb, list)
                    and len(tb) == len(names) and len(cb) == len(names)):
                fail("%s: the best values are not lists indexed by 'workloads'" % path)
        else:
            if len(names) != 1:
                fail("%s: expected one workload" % path)
            tb, cb = [tb], [cb]
        for i, name in enumerate(names):
            for v in (tb[i], cb[i]):
                if not isinstance(v, Decimal):
                    fail("%s: a best value of %s is not a number" % (path, name))
            best[name] = (tb[i], cb[i])
    for name in WORKLOADS:
        if name not in best:
            fail("no MATLAB baseline for %s" % name)
    return best, machines


# ---------------------------------------------------------------------------------------
# Recomputation of the summary from the runs (exact, decimal; L-pv)
# ---------------------------------------------------------------------------------------

def fmt(d, places):
    return format(d.quantize(Decimal(1).scaleb(-places)), "f")


def stats(walls, comps):
    """walls, comps: lists of 15 Decimals (runs 1..15) -> the twelve summary strings."""
    out = []
    for vals, p, p10 in ((walls, 9, 10), (comps, 3, 4)):
        first = vals[0]
        s5 = sorted(vals[:5])
        s10 = sorted(vals[5:])
        med10 = (s10[4] + s10[5]) / 2
        out += [fmt(first, p), fmt(s5[0], p), fmt(s5[2], p), fmt(med10, p10),
                fmt(s10[0], p), fmt(s10[9], p)]
    return out


def load_runs(path):
    rows = read_tsv(path, RUNS_HEADER)
    runs = {}
    for r in rows:
        if r["target"] != TARGET:
            fail("%s: target '%s' is not %s" % (path, r["target"], TARGET))
        if r["variant"] != VARIANT:
            fail("%s: variant '%s' is not %s" % (path, r["variant"], VARIANT))
        name = r["workload"]
        if name not in WORKLOADS:
            fail("%s: unexpected workload '%s'" % (path, name))
        if not re.match(r"^[1-9][0-9]*$", r["run"]):
            fail("%s: bad run number '%s'" % (path, r["run"]))
        k = int(r["run"])
        if not WALL_RE.match(r["wall_s"]) or not WALL_RE.match(r["cpu_s"]):
            fail("%s: %s run %d: wall or cpu time not in %%.9f form" % (path, name, k))
        if not COMP_RE.match(r["compute_s"]):
            fail("%s: %s run %d: compute time not in %%.3f form" % (path, name, k))
        if not re.match(r"^[0-9]+$", r["status"]) or int(r["status"]) != 0:
            fail("%s: %s run %d: status %s, not 0" % (path, name, k, r["status"]))
        d = runs.setdefault(name, {})
        if k in d:
            fail("%s: %s run %d repeated" % (path, name, k))
        d[k] = (Decimal(r["wall_s"]), Decimal(r["compute_s"]))
    for name in WORKLOADS:
        if name not in runs:
            fail("%s: workload %s missing" % (path, name))
        if sorted(runs[name]) != list(range(1, 16)):
            fail("%s: %s has runs %s, not exactly 1-15" % (path, name, sorted(runs[name])))
    return {n: ([runs[n][k][0] for k in range(1, 16)], [runs[n][k][1] for k in range(1, 16)])
            for n in WORKLOADS}


def load_summary(path, runs):
    rows = read_tsv(path, SUMMARY_HEADER)
    seen = {}
    for r in rows:
        if r["target"] != TARGET or r["variant"] != VARIANT:
            fail("%s: row for %s/%s, expected %s/%s"
                 % (path, r["target"], r["variant"], TARGET, VARIANT))
        name = r["workload"]
        if name not in WORKLOADS:
            fail("%s: unexpected workload '%s'" % (path, name))
        if name in seen:
            fail("%s: workload %s repeated" % (path, name))
        seen[name] = r
    for name in WORKLOADS:
        if name not in seen:
            fail("%s: workload %s missing" % (path, name))
        want = stats(*runs[name])
        for col, w in zip(SUMMARY_CHECKED, want):
            if seen[name][col] != w:
                fail("%s: %s %s is '%s' but the runs give '%s'"
                     % (path, name, col, seen[name][col], w))
    return seen


# ---------------------------------------------------------------------------------------
# The check
# ---------------------------------------------------------------------------------------

def load_avg(value, key, path):
    nums = re.findall(r"[0-9]+(?:\.[0-9]+)?", value)
    if not nums:
        fail("%s: '%s' holds no load average (%s)" % (path, key, value))
    return Decimal(nums[0])


def require_marker(dirpath, tool, target):
    """C2: a final-mode result file has its attempt marker directory."""
    m = os.path.join(dirpath, ".attempt-%s-%s" % (tool, target))
    if not os.path.isdir(m):
        fail("attempt marker %s is missing" % m)


def run_check(dirpath, refdir=REFDIR):
    """-> (exit code, standard output text); raises SetupError."""
    wenv_path = os.path.join(dirpath, "env-workloads-%s.txt" % TARGET)
    sess = read_text(os.path.join(dirpath, "session.txt"))
    if not sess.endswith("\n") or sess.count("\n") != 1 or not sess.strip():
        fail("malformed %s" % os.path.join(dirpath, "session.txt"))
    session = sess[:-1]

    wenv = read_env(wenv_path)
    if need(wenv, "mode", wenv_path) != "final":
        fail("%s: mode is '%s', not final" % (wenv_path, wenv["mode"]))
    if need(wenv, "sea_dirty", wenv_path) != "no":
        fail("%s: sea_dirty is '%s', not no" % (wenv_path, wenv["sea_dirty"]))
    if need(wenv, "baysick_dirty", wenv_path) != "no":
        fail("%s: baysick_dirty is '%s', not no" % (wenv_path, wenv["baysick_dirty"]))
    if need(wenv, "target", wenv_path) != TARGET:
        fail("%s: target is '%s', not %s" % (wenv_path, wenv["target"], TARGET))
    if need(wenv, "session", wenv_path) != session:
        fail("%s: session differs from session.txt" % wenv_path)
    commit = need(wenv, "sea_commit", wenv_path)
    bcommit = need(wenv, "baysick_commit", wenv_path)
    require_marker(dirpath, "workloads", TARGET)
    for key in ("date", "machine_model", "cpu", "load_before", "load_after"):
        need(wenv, key, wenv_path)

    # Every other record present belongs to the same session and commit (L-ps).
    try:
        names = sorted(os.listdir(dirpath))
    except OSError as e:
        fail("cannot read %s: %s" % (dirpath, e.strerror or e))
    for fn in names:
        if not (fn.startswith("env-") and fn.endswith(".txt")):
            continue
        p = os.path.join(dirpath, fn)
        if p == wenv_path:
            continue
        stem = fn[4:-4]
        for t in ("workloads", "kernels", "micro", "numpy"):
            if stem.startswith(t + "-"):
                require_marker(dirpath, t, stem[len(t) + 1:])
        e = read_env(p)
        if need(e, "session", p) != session:
            fail("%s: session '%s' differs from session.txt" % (p, e["session"]))
        if need(e, "sea_commit", p) != commit:
            fail("%s: sea_commit '%s' differs from the workloads record's" % (p, e["sea_commit"]))
        if need(e, "baysick_commit", p) != bcommit:
            fail("%s: baysick_commit '%s' differs from the workloads record's"
                 % (p, e["baysick_commit"]))

    best, machines = read_matlab(refdir)
    runs = load_runs(os.path.join(dirpath, "workloads-runs-%s.tsv" % TARGET))
    load_summary(os.path.join(dirpath, "workloads-%s.tsv" % TARGET), runs)
    lb = load_avg(wenv["load_before"], "load_before", wenv_path)
    la = load_avg(wenv["load_after"], "load_after", wenv_path)

    machine_ok = all(m == wenv["machine_model"] and c == wenv["cpu"] for _, m, c in machines)
    bm = []
    bc = []
    for _, m, c in machines:
        if m not in bm:
            bm.append(m)
        if c not in bc:
            bc.append(c)

    out = []
    out.append("sea bench check: %s, session %s, sea commit %s, %s"
               % (TARGET, session, commit, wenv["date"]))
    out.append("machine: %s (%s); baseline %s (%s): %s"
               % (wenv["machine_model"], wenv["cpu"], "/".join(bm), "/".join(bc),
                  "ok" if machine_ok else "MISMATCH"))
    out.append("load average before %s; after %s" % (wenv["load_before"], wenv["load_after"]))
    if lb > Decimal("2.0") or la > Decimal("2.0"):
        out.append("warning: load average above 2.0")
    misses = []
    for name in WORKLOADS:
        walls, comps = runs[name]
        wu = min(walls[:5]) + WALL_ULP
        cu = min(comps[:5]) + COMP_ULP
        mt, mc = best[name]
        w_ok = wu < mt
        c_ok = cu < mc
        out.append("%-16s wall %s %s %.6f %s   compute %s %s %.6f %s" % (
            name, fmt(wu, 10), "<" if w_ok else ">=", float(mt), "ok" if w_ok else "MISS",
            fmt(cu, 4), "<" if c_ok else ">=", float(mc), "ok" if c_ok else "MISS"))
        if not (w_ok and c_ok):
            what = "wall, compute" if not w_ok and not c_ok else ("wall" if not w_ok else "compute")
            misses.append((name, what))
    if not machine_ok:
        out.append("FAIL: measured on another machine than the MATLAB baseline")
        code = 1
    elif misses:
        out.append("FAIL: %d of 7 workloads miss: %s"
                   % (len(misses), ", ".join("%s (%s)" % m for m in misses)))
        code = 1
    else:
        out.append("PASS: 7 of 7 workloads faster than MATLAB on both measures")
        code = 0
    return code, "\n".join(out) + "\n"


# ---------------------------------------------------------------------------------------
# Self-test: synthetic fixtures (test inputs for the checker, never measurements)
# ---------------------------------------------------------------------------------------

def _scaled(s, places):
    """'0.123456789' -> integer count of 10**-places."""
    a, b = s.split(".")
    return int(a) * 10 ** places + int(b)


def _unscale(n, places):
    return "%d.%0*d" % (n // 10 ** places, places, n % 10 ** places)


def _fixture_stats(walls, comps):
    """The twelve summary strings by integer arithmetic (independent of stats())."""
    out = []
    for vals, p in ((walls, 9), (comps, 3)):
        v = [_scaled(s, p) for s in vals]
        s5 = sorted(v[:5])
        s10 = sorted(v[5:])
        two = s10[4] + s10[5]  # twice the median, in 10**-p units
        # one more decimal: median = two / 2 = two * 5 in 10**-(p+1) units
        out += [vals[0], _unscale(s5[0], p), _unscale(s5[2], p), _unscale(two * 5, p + 1),
                _unscale(s10[0], p), _unscale(s10[9], p)]
    return out


def build_fixture(root, best, overrides=None):
    """Write a passing result directory under root. `best` maps workload -> (Mt, Mc) Decimals.
    overrides: dict with optional keys 'env' (dict of env changes), 'runs' (fn(name, walls,
    comps) -> (walls, comps) string lists), 'drop' (workload to omit), 'summary' (fn(name,
    cols list) -> cols list), 'extra_env' (dict filename -> dict), 'session'."""
    ov = overrides or {}
    os.makedirs(root, exist_ok=True)
    session = ov.get("session", "20261105T091500Z-3fa9c21e")
    with open(os.path.join(root, "session.txt"), "w") as f:
        f.write(session + "\n")
    env = {
        "target": TARGET, "mode": "final", "session": session,
        "date": "2026-11-05T09:15:00Z", "machine_model": "Mac14,9", "cpu": "Apple M2 Pro",
        "os": "macOS 26.0 (Darwin 25.0.0)", "sea_commit": "0123456789abcdef0123456789abcdef01234567",
        "sea_dirty": "no", "baysick_commit": "fedcba9876543210fedcba9876543210fedcba98",
        "baysick_dirty": "no", "nice": "0", "power": "ac", "lowpower": "0", "variants": "neon",
        "tools": "fixture", "settle_waited_s": "0", "load_before": "1.10 1.20 1.30",
        "load_after": "1.15 1.20 1.30",
    }
    env.update(ov.get("env", {}))
    with open(os.path.join(root, "env-workloads-%s.txt" % TARGET), "w") as f:
        for k, v in env.items():
            f.write("%s\t%s\n" % (k, v))
    if not ov.get("no_marker"):
        os.makedirs(os.path.join(root, ".attempt-workloads-%s" % TARGET), exist_ok=True)
    for fn, d in ov.get("extra_env", {}).items():
        stem = fn[4:-4]
        if not ov.get("no_marker"):
            os.makedirs(os.path.join(root, ".attempt-" + stem), exist_ok=True)
        e = {"target": "x", "mode": "final", "session": session, "sea_commit": env["sea_commit"],
             "baysick_commit": env["baysick_commit"]}
        e.update(d)
        with open(os.path.join(root, fn), "w") as f:
            for k, v in e.items():
                f.write("%s\t%s\n" % (k, v))
    if ov.get("drop_marker"):
        os.rmdir(os.path.join(root, ov["drop_marker"]))
    runs_lines = ["\t".join(RUNS_HEADER)]
    sum_lines = ["\t".join(SUMMARY_HEADER)]
    for i, name in enumerate(WORKLOADS):
        if name == ov.get("drop"):
            continue
        mt, mc = best[name]
        base_w = int(mt * Decimal(10) ** 9 * Decimal("0.5"))
        base_c = int(mc * Decimal(10) ** 3 * Decimal("0.5"))
        walls = [_unscale(base_w + base_w * ((k * 7) % 11) // 100, 9) for k in range(15)]
        comps = [_unscale(base_c + base_c * ((k * 5) % 13) // 100, 3) for k in range(15)]
        if "runs" in ov:
            walls, comps = ov["runs"](name, walls, comps)
        for k in range(len(walls)):
            runs_lines.append("\t".join([
                TARGET, VARIANT, name, str(k + 1), walls[k], _unscale(_scaled(walls[k], 9) // 2, 9),
                comps[k], "0"]))
        cols = _fixture_stats(walls, comps) if len(walls) == 15 else ["0"] * 12
        if "summary" in ov:
            cols = ov["summary"](name, cols)
        sum_lines.append("\t".join([TARGET, env["cpu"], VARIANT, name, "0.500"] + cols))
    with open(os.path.join(root, "workloads-runs-%s.tsv" % TARGET), "w") as f:
        f.write("\n".join(runs_lines) + "\n")
    with open(os.path.join(root, "workloads-%s.tsv" % TARGET), "w") as f:
        f.write("\n".join(sum_lines) + "\n")


def _with_best(name, wall=None, comp=None):
    """runs override: for `name` make the 15 runs' walls/compute times best + increasing."""
    def fn(n, walls, comps):
        if n != name:
            return walls, comps
        if wall is not None:
            b = _scaled(wall, 9)
            walls = [_unscale(b + k * 1000, 9) for k in range(15)]
        if comp is not None:
            b = _scaled(comp, 3)
            comps = [_unscale(b + k, 3) for k in range(15)]
        return walls, comps
    return fn


def self_test():
    import shutil
    import subprocess
    import tempfile

    best, _ = read_matlab(REFDIR)
    results = []
    tmp = tempfile.mkdtemp(prefix="seacheck-")

    def case(label, ov, want_code, in_out=(), not_in_out=(), err=None):
        d = os.path.join(tmp, "c%d" % len(results))
        build_fixture(d, best, ov)
        try:
            code, text = run_check(d)
            got_err = None
        except SetupError as e:
            code, text, got_err = 2, "", str(e)
        ok = code == want_code
        for s in in_out:
            ok = ok and s in text
        for s in not_in_out:
            ok = ok and s not in text
        if want_code == 2:
            ok = ok and text == "" and got_err is not None and (err is None or err in got_err)
        results.append(ok)
        print("  %s %s (exit %d)%s" % ("ok  " if ok else "FAIL", label, code,
                                       "" if ok else "  -- got: %r %r" % (text, got_err)))

    w8t = best["w8_ev_can"][0]
    w8_round = fmt(w8t, 9)                            # MATLAB's best rounded to 9 decimals
    w8_below = _unscale(_scaled(w8_round, 9) - 1, 9)  # one unit below
    print("check self-test (synthetic fixtures in %s):" % tmp)
    try:
        case("all seven pass", None, 0,
             ["PASS: 7 of 7 workloads faster than MATLAB on both measures",
              "machine: Mac14,9 (Apple M2 Pro); baseline Mac14,9 (Apple M2 Pro): ok"],
             ["MISS", "warning"])
        case("W7/W8 files read as scalars", None, 0,
             ["w7_drivetrain    wall ", "< 8.625048 ok", "< 0.625959 ok", "< 0.617082 ok"])
        case("best wall = MATLAB best rounded to 9 decimals -> MISS",
             {"runs": _with_best("w8_ev_can", wall=w8_round)}, 1,
             ["FAIL: 1 of 7 workloads miss: w8_ev_can (wall)", ">= 0.625959 MISS"])
        case("best wall one unit below that -> ok",
             {"runs": _with_best("w8_ev_can", wall=w8_below)}, 0, ["PASS"])
        case("printed compute 0.617 vs 0.61708195833333335 -> cu 0.6175 MISS",
             {"runs": _with_best("w8_ev_can", comp="0.617")}, 1,
             ["compute 0.6175 >= 0.617082 MISS", "w8_ev_can (compute)"])
        case("printed compute 0.616 -> cu 0.6165 ok",
             {"runs": _with_best("w8_ev_can", comp="0.616")}, 0,
             ["compute 0.6165 < 0.617082 ok"])
        case("misses on both measures and on one, in workload order",
             {"runs": lambda n, w, c: (
                 (_with_best("w1_shaft_design", "9.000000000", "9.000")(n, w, c)
                  if n == "w1_shaft_design" else
                  _with_best("w3_quarter_car", wall="9.000000000")(n, w, c))
                 )}, 1,
             ["FAIL: 2 of 7 workloads miss: w1_shaft_design (wall, compute), w3_quarter_car (wall)"])
        case("a workload missing -> setup error", {"drop": "w5_tolerance_mc"}, 2, err="w5_tolerance_mc")
        case("mode quick -> setup error", {"env": {"mode": "quick"}}, 2, err="not final")
        case("sea_dirty yes -> setup error", {"env": {"sea_dirty": "yes"}}, 2, err="sea_dirty")
        case("baysick_dirty yes -> setup error", {"env": {"baysick_dirty": "yes"}}, 2,
             err="baysick_dirty")
        case("target not arm64-macos -> setup error", {"env": {"target": "x86_64-linux"}}, 2,
             err="target")
        case("env-kernels with another session -> setup error",
             {"extra_env": {"env-kernels-arm64-macos.txt": {"session": "other"}}}, 2,
             err="session")
        case("env-kernels with another commit -> setup error",
             {"extra_env": {"env-kernels-arm64-macos.txt": {"sea_commit": "abc"}}}, 2,
             err="sea_commit")
        case("env-kernels of the same session and commit is accepted",
             {"extra_env": {"env-kernels-arm64-macos.txt": {}}}, 0, ["PASS"])
        case("env-kernels with another baysick_commit -> setup error",
             {"extra_env": {"env-kernels-arm64-macos.txt": {"baysick_commit": "abc"}}}, 2,
             err="baysick_commit")
        case("attempt marker of the workloads record missing -> setup error",
             {"no_marker": True}, 2, err="attempt marker")
        case("attempt marker of an env-kernels file missing -> setup error",
             {"extra_env": {"env-kernels-arm64-macos.txt": {}},
              "drop_marker": ".attempt-kernels-arm64-macos"}, 2,
             err=".attempt-kernels-arm64-macos")
        case("mixed sessions: workloads record from another session",
             {"env": {"session": "20260101T000000Z-00000000"}}, 2, err="session")
        case("a run missing (14 runs) -> setup error",
             {"runs": lambda n, w, c: (w[:14], c[:14]) if n == "w2_truss_fem" else (w, c)}, 2,
             err="not exactly 1-15")

        def bad_median10_wall(n, cols):
            if n == "w4_heat_plate":
                cols[3] = cols[3][:-1] + ("0" if cols[3][-1] != "0" else "1")
            return cols
        case("summary disagrees with the runs -> setup error",
             {"summary": bad_median10_wall}, 2, err="median10_wall_s")

        def short_median10_comp(n, cols):
            if n == "w4_heat_plate":
                cols[9] = cols[9][:-1]
            return cols
        case("median of 10 compute written with 3 decimals -> setup error",
             {"summary": short_median10_comp}, 2, err="median10_compute_s")

        def bad_best(n, cols):
            if n == "w1_shaft_design":
                cols[1] = cols[0]
            return cols
        case("summary best differs from the runs' minimum -> setup error",
             {"runs": lambda n, w, c: (w[::-1], c) if n == "w1_shaft_design" else (w, c),
              "summary": bad_best}, 2, err="best5_wall_s")
        case("machine model Mac15,7 -> MISMATCH, exit 1",
             {"env": {"machine_model": "Mac15,7"}}, 1,
             ["Mac15,7 (Apple M2 Pro); baseline Mac14,9 (Apple M2 Pro): MISMATCH",
              "FAIL: measured on another machine than the MATLAB baseline", "w1_shaft_design"])
        case("another cpu name -> MISMATCH",
             {"env": {"cpu": "Apple M3"}}, 1, ["MISMATCH"])
        case("load 2.5 -> warning, verdict unchanged",
             {"env": {"load_before": "2.50 1.20 1.30"}}, 0,
             ["load average before 2.50 1.20 1.30; after 1.15 1.20 1.30\n"
              "warning: load average above 2.0\n", "PASS"])
        case("load exactly 2.0 -> no warning",
             {"env": {"load_after": "2.00 1.20 1.30"}}, 0, ["PASS"], ["warning"])

        # The command line: exit status and streams of a real invocation.
        d = os.path.join(tmp, "cli")
        build_fixture(d, best)
        r = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), d],
                           capture_output=True, text=True)
        ok = r.returncode == 0 and r.stdout.startswith("sea bench check: arm64-macos, session ")
        results.append(ok)
        print("  %s command line on a passing directory (exit %d)"
              % ("ok  " if ok else "FAIL", r.returncode))
        d = os.path.join(tmp, "cli2")
        build_fixture(d, best, {"env": {"mode": "quick"}})
        r = subprocess.run([sys.executable, "-I", os.path.abspath(__file__), d],
                           capture_output=True, text=True)
        ok = r.returncode == 2 and r.stdout == "" and r.stderr.startswith("check: ") \
            and r.stderr.count("\n") == 1
        results.append(ok)
        print("  %s command line on a quick-mode directory (exit %d, stderr %r)"
              % ("ok  " if ok else "FAIL", r.returncode, r.stderr))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    p = sum(1 for x in results if x)
    f = len(results) - p
    print("check self-test: %d passed, %d failed" % (p, f))
    return 0 if f == 0 else 1


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) > 1 or (argv and argv[0].startswith("-")):
        sys.stderr.write("check: usage: check.py [DIR] | --self-test\n")
        return 2
    dirpath = argv[0] if argv else DEFAULT_DIR
    try:
        code, text = run_check(dirpath)
    except SetupError as e:
        sys.stderr.write("check: %s\n" % e)
        return 2
    sys.stdout.write(text)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
