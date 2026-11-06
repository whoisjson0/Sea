#!/usr/bin/env python3
# charts.py -- the README benchmark charts (docs/DESIGN.md section 2.17.9, L-pn, L-qv).
#
# Purpose:  write, from the result files of DIR and the MATLAB baseline files, the SVG charts of
#           the README: speedup-{light,dark}.svg (MATLAB best / Sea best, whole process and
#           compute, log scale) and times-{light,dark}.svg (whole-process seconds, Sea against
#           MATLAB, one panel and one scale per workload). Every number is read from a file
#           through bench/report.py's own parsing; none is typed by hand.
# Usage:    uv run --no-project python -I bench/charts.py DIR OUTDIR
# Input:    DIR/session.txt, DIR/env-workloads-arm64-macos.txt, DIR/workloads-arm64-macos.tsv
#           and workloads/reference/baseline_timings_matlab*.json (the default-threads files),
#           all read exactly as report.py reads them.
# Output:   OUTDIR/speedup-light.svg, speedup-dark.svg, times-light.svg, times-dark.svg
#           (OUTDIR is created when missing). The same input gives byte-identical files: no
#           clock, no environment, fixed number formats.
# Exit:     0 written; 2 a missing or malformed input file, or a layout that would overflow
#           or collide (one line "charts: <reason>").
# Library:  the Python standard library only (L-pq).

import importlib.util
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_report():
    """bench/report.py as a module (python -I leaves the script directory off sys.path)."""
    spec = importlib.util.spec_from_file_location("bsk_report", os.path.join(HERE, "report.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


report = load_report()
fail = report.fail

# ---------------------------------------------------------------------------------------
# Colours: two themes, one for GitHub's light page (#ffffff) and one for its dark page
# (#0d1117); the background stays transparent. Series colours are the dataviz reference
# palette's slots 1 and 2, validated (validate_palette.js) against both page colours.
# ---------------------------------------------------------------------------------------

THEMES = {
    "light": {
        "ink": "#1f2328", "ink2": "#52514e", "muted": "#6e6c66",
        "grid": "#e1e0d9", "axis": "#c3c2b7", "ref": "#52514e",
        "s1": "#2a78d6", "s2": "#eb6834",
    },
    "dark": {
        "ink": "#f0efec", "ink2": "#c3c2b7", "muted": "#9a988f",
        "grid": "#2c2f33", "axis": "#4a4d52", "ref": "#c3c2b7",
        "s1": "#3987e5", "s2": "#d95926",
    },
}

FONT = "system-ui, -apple-system, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif"
WIDTH = 800
GUTTER = 24

# Words of the workload ids written in capitals in the readable names.
ACRONYMS = {"fem", "mc", "ev", "can"}


def pretty_name(wid):
    """w1_shaft_design -> 'W1 shaft design' (ACRONYMS in capitals)."""
    parts = wid.split("_")
    out = [parts[0].upper()]
    for p in parts[1:]:
        out.append(p.upper() if p in ACRONYMS else p)
    return " ".join(out)


def g(x):
    """A coordinate: at most 2 decimals, no trailing zeros (deterministic)."""
    s = "%.2f" % x
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


# Approximate advance widths (em) of a system sans, slightly generous, for layout checks.
NARROW = set("iljI.,:;'|!()[] ")
WIDE = set("mwMW%@")


def text_width(s, size, bold=False):
    w = 0.0
    for c in s:
        if c in NARROW:
            w += 0.30
        elif c in WIDE:
            w += 0.86
        elif c.isupper() or c.isdigit():
            w += 0.64
        elif c == "×":
            w += 0.60
        else:
            w += 0.55
    return w * size * (1.06 if bold else 1.0)


class Svg:
    """Collects elements and text boxes; refuses text that leaves the view or collides."""

    def __init__(self, theme):
        self.t = THEMES[theme]
        self.els = []
        self.boxes = []   # (x0, y0, x1, y1, label)

    def add(self, s):
        self.els.append(s)

    def text(self, x, y, s, size, fill, anchor="start", bold=False, check=True):
        w = text_width(s, size, bold)
        x0 = {"start": x, "middle": x - w / 2, "end": x - w}[anchor]
        if check:
            self.boxes.append((x0, y - size * 0.78, x0 + w, y + size * 0.22, s))
        attrs = ['x="%s"' % g(x), 'y="%s"' % g(y), 'font-size="%s"' % g(size),
                 'fill="%s"' % fill]
        if anchor != "start":
            attrs.append('text-anchor="%s"' % anchor)
        if bold:
            attrs.append('font-weight="600"')
        self.add("<text %s>%s</text>" % (" ".join(attrs), esc(s)))

    def rect_box(self, x0, y0, x1, y1, label):
        self.boxes.append((min(x0, x1), y0, max(x0, x1), y1, label))

    def line(self, x1, y1, x2, y2, stroke, width=1):
        self.add('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"/>' % (
            g(x1), g(y1), g(x2), g(y2), stroke, g(width)))

    def hbar(self, xb, xe, y, h, fill, label):
        """A horizontal bar from the baseline xb to the data end xe: 4px rounded data end,
        square at the baseline."""
        w = abs(xe - xb)
        r = min(4.0, w, h / 2)
        if xe >= xb:
            d = "M%s %sH%sA%s %s 0 0 1 %s %sV%sA%s %s 0 0 1 %s %sH%sZ" % (
                g(xb), g(y), g(xe - r), g(r), g(r), g(xe), g(y + r), g(y + h - r),
                g(r), g(r), g(xe - r), g(y + h), g(xb))
        else:
            d = "M%s %sH%sA%s %s 0 0 0 %s %sV%sA%s %s 0 0 0 %s %sH%sZ" % (
                g(xb), g(y), g(xe + r), g(r), g(r), g(xe), g(y + r), g(y + h - r),
                g(r), g(r), g(xe + r), g(y + h), g(xb))
        self.add('<path d="%s" fill="%s"/>' % (d, fill))
        self.rect_box(xb, y, xe, y + h, label)

    def swatch(self, x, y, fill):
        self.add('<rect x="%s" y="%s" width="12" height="12" rx="2" fill="%s"/>' % (
            g(x), g(y), fill))
        self.rect_box(x, y, x + 12, y + 12, "swatch")

    def finish(self, height, title, desc, ident):
        for (x0, y0, x1, y1, s) in self.boxes:
            if x0 < 0 or x1 > WIDTH or y0 < 0 or y1 > height:
                fail("%s: '%s' leaves the %dx%d view" % (ident, s, WIDTH, height))
        n = len(self.boxes)
        for i in range(n):
            a = self.boxes[i]
            for j in range(i + 1, n):
                b = self.boxes[j]
                if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]:
                    fail("%s: '%s' collides with '%s'" % (ident, a[4], b[4]))
        head = ['<?xml version="1.0" encoding="UTF-8"?>',
                '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                'viewBox="0 0 %d %d" role="img" aria-labelledby="%s-title %s-desc" '
                'font-family="%s">' % (WIDTH, height, WIDTH, height, ident, ident, FONT),
                '<title id="%s-title">%s</title>' % (ident, esc(title)),
                '<desc id="%s-desc">%s</desc>' % (ident, esc(desc))]
        return "\n".join(head + self.els + ["</svg>"]) + "\n"


# ---------------------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------------------

def matlab_facts():
    """(release, threads, repeats) of the default-threads MATLAB files; they must agree."""
    facts = set()
    for fn in ("baseline_timings_matlab.json", "baseline_timings_matlab_w7_drivetrain.json",
               "baseline_timings_matlab_w8_ev_can.json"):
        d = report.read_matlab_file(fn)
        m = re.search(r"\((R\d{4}[ab])\)", str(d.get("matlab_version", "")))
        thr = d.get("max_num_comp_threads")
        rep = d.get("n_repeat")
        if m is None or not isinstance(thr, int) or not isinstance(rep, int):
            fail("%s: no MATLAB release, thread count or repeat count" % fn)
        facts.add((m.group(1), thr, rep))
    if len(facts) != 1:
        fail("the default-threads MATLAB files differ in release, threads or repeats")
    return facts.pop()


def load(dirpath):
    data = report.Data(dirpath)
    summ = report.mac_summary(data)
    ml = report.matlab_default()
    env = data.env.get(("workloads", report.MAC))
    if env is None:
        fail("env-workloads-%s.txt is missing in %s" % (report.MAC, dirpath))
    rows = []
    for n in report.WORKLOADS:
        r, m = summ[n], ml[n]
        sw = report.num(r["best5_wall_s"])
        sc = report.num(r["best5_compute_s"])
        mw, mc = float(m["bt"]), float(m["bc"])
        rows.append({"id": n, "name": pretty_name(n), "sea_wall": sw, "sea_comp": sc,
                     "ml_wall": mw, "ml_comp": mc, "r_wall": mw / sw, "r_comp": mc / sc})
    release, threads, reps = matlab_facts()
    info = {
        "machine": "%s (%s), %s" % (env.get("machine_model", "-"), env.get("cpu", "-"),
                                    env.get("os", "-")),
        "commit": env.get("sea_commit", "-")[:7],
        "session": data.session,
        "release": release, "threads": threads, "reps": reps,
    }
    return rows, info


def footer_lines(info):
    return [
        "MATLAB %s with %d threads, in-session; Sea single-threaded, whole process." % (
            info["release"], info["threads"]),
        "%s · Sea commit %s · session %s" % (info["machine"], info["commit"],
                                            info["session"]),
    ]


def ratio_label(r):
    return "%.1f×" % r


# ---------------------------------------------------------------------------------------
# Chart 1: times faster, log scale
# ---------------------------------------------------------------------------------------

def log_ticks(lo, hi):
    """1-2-5 ticks covering [lo, hi] (lo <= 1 <= hi), as (value, label)."""
    out = []
    e = math.floor(math.log10(lo))
    while True:
        for m in (1, 2, 5):
            v = m * 10.0 ** e
            if v >= lo * 0.999999 and v <= hi * 1.000001:
                lab = ("%d" % round(v)) if v >= 1 else ("%g" % v)
                out.append((v, lab + "×"))
        if 10.0 ** (e + 1) > hi * 1.000001:
            break
        e += 1
    return out


def nice_up(x):
    """The smallest 1-2-5 value >= x."""
    e = math.floor(math.log10(x))
    for m in (1, 2, 5, 10):
        v = m * 10.0 ** e
        if v >= x * 0.999999:
            return v
    return 10.0 ** (e + 1)


def nice_down(x):
    e = math.floor(math.log10(x))
    for m in (5, 2, 1):
        v = m * 10.0 ** e
        if v <= x * 1.000001:
            return v
    return 10.0 ** (e - 1)


def speedup_svg(rows, info, theme):
    ident = "speedup-" + theme
    s = Svg(theme)
    t = s.t
    x0, x1 = 176.0, WIDTH - 72.0
    rmin = min(min(r["r_wall"], r["r_comp"]) for r in rows)
    rmax = max(max(r["r_wall"], r["r_comp"]) for r in rows)
    lo = min(1.0, nice_down(rmin))
    hi = max(1.0, nice_up(rmax))
    llo, lhi = math.log10(lo), math.log10(hi)
    X = lambda v: x0 + (x1 - x0) * (math.log10(v) - llo) / (lhi - llo)

    s.text(GUTTER, 34, "Sea vs MATLAB: times faster (higher is better)", 20, t["ink"],
           bold=True)
    s.text(GUTTER, 57, "MATLAB best time ÷ Sea best time, per workload (log scale)", 13,
           t["ink2"])
    # Legend, right-aligned on its own line.
    items = [("s1", "Whole process"), ("s2", "Compute (timed region)")]
    widths = [12 + 6 + text_width(lab, 12) for _, lab in items]
    lx = WIDTH - GUTTER - (sum(widths) + 20 * (len(items) - 1))
    for (key, lab), w in zip(items, widths):
        s.swatch(lx, 75, t[key])
        s.text(lx + 18, 85.5, lab, 12, t["ink2"])
        lx += w + 20

    top = 112.0
    row_h = 46.0
    bar_h = 14.0
    gap = 2.0
    bottom = top + row_h * len(rows)
    # Gridlines and tick labels.
    for v, lab in log_ticks(lo, hi):
        x = X(v)
        if abs(v - 1.0) > 1e-9:
            s.line(x, top, x, bottom, t["grid"])
        s.text(x, bottom + 18, lab, 12, t["muted"], anchor="middle")
    # Rows.
    for i, r in enumerate(rows):
        yc = top + row_h * i + row_h / 2
        s.text(GUTTER, yc + 4.5, r["name"], 13, t["ink"])
        for k, (key, val) in enumerate((("s1", r["r_wall"]), ("s2", r["r_comp"]))):
            y = yc - bar_h - gap / 2 + k * (bar_h + gap)
            xe = X(val)
            s.hbar(X(1.0), xe, y, bar_h, t[key], "%s bar %d" % (r["id"], k))
            lab = ratio_label(val)
            if xe >= X(1.0):
                s.text(xe + 6, y + bar_h - 3, lab, 12, t["ink"])
            else:
                s.text(xe - 6, y + bar_h - 3, lab, 12, t["ink"], anchor="end")
    # The MATLAB reference line at 1x, drawn over the bar baselines.
    xr = X(1.0)
    s.line(xr, top - 4, xr, bottom, t["ref"], 1.5)
    s.text(xr, top - 10, "MATLAB", 12, t["ink2"], anchor="middle", bold=True)

    fy = bottom + 50
    f1, f2 = footer_lines(info)
    s.text(GUTTER, fy, f1, 12, t["ink2"])
    s.text(GUTTER, fy + 18, "Whole process: Sea's process vs MATLAB's in-session total. "
           "Compute: the same timed region in both. Best of %d runs each." % info["reps"],
           12, t["ink2"])
    s.text(GUTTER, fy + 36, f2, 11, t["muted"])
    height = int(fy + 36 + 18)

    title = "Sea vs MATLAB: times faster (higher is better)"
    desc = ("How many times faster Sea is than MATLAB on each workload, as MATLAB's best "
            "time divided by Sea's best time. " +
            "; ".join("%s: whole process %s, compute %s" % (
                r["name"], ratio_label(r["r_wall"]), ratio_label(r["r_comp"])) for r in rows) +
            ". " + f1 + " " + f2)
    return s.finish(height, title, desc, ident)


# ---------------------------------------------------------------------------------------
# Chart 2: whole-process seconds, small multiples
# ---------------------------------------------------------------------------------------

def lin_ticks(vmax):
    """Ticks 0..top for one panel: a 1-2-5 step giving 3-5 intervals; (top, [(v, label)])."""
    raw = vmax / 3.0
    e = math.floor(math.log10(raw))
    step = None
    for m in (1, 2, 5, 10):
        if m * 10.0 ** e >= raw * 0.999999:
            step = m * 10.0 ** e
            break
    n = int(math.ceil(vmax / step - 1e-9))
    dec = max(0, -int(math.floor(math.log10(step) + 1e-9)))
    ticks = [(i * step, "%.*f" % (dec, i * step)) for i in range(n + 1)]
    return n * step, ticks


def times_svg(rows, info, theme):
    ident = "times-" + theme
    s = Svg(theme)
    t = s.t
    s.text(GUTTER, 34, "Whole-process time: Sea vs MATLAB (lower is better)", 20, t["ink"],
           bold=True)
    s.text(GUTTER, 57, "Seconds, best of %d runs. Each workload has its own scale." %
           info["reps"], 13, t["ink2"])
    items = [("s1", "Sea"), ("s2", "MATLAB")]
    widths = [12 + 6 + text_width(lab, 12) for _, lab in items]
    lx = WIDTH - GUTTER - (sum(widths) + 20 * (len(items) - 1))
    for (key, lab), w in zip(items, widths):
        s.swatch(lx, 75, t[key])
        s.text(lx + 18, 85.5, lab, 12, t["ink2"])
        lx += w + 20

    cols = 2
    col_gap = 32.0
    pw = (WIDTH - 2 * GUTTER - col_gap * (cols - 1)) / cols
    ph = 118.0
    top0 = 112.0
    bar_h = 16.0
    nrows = (len(rows) + cols - 1) // cols
    for i, r in enumerate(rows):
        px = GUTTER + (i % cols) * (pw + col_gap)
        py = top0 + (i // cols) * ph
        s.text(px, py + 12, r["name"], 13, t["ink"], bold=True)
        bx0 = px + 64.0
        bx1 = px + pw - 64.0
        vtop, ticks = lin_ticks(max(r["sea_wall"], r["ml_wall"]))
        X = lambda v: bx0 + (bx1 - bx0) * v / vtop
        yb = py + 26.0
        yend = yb + 2 * bar_h + 8.0
        for v, lab in ticks:
            x = X(v)
            s.line(x, yb - 4, x, yend + 4, t["axis"] if v == 0 else t["grid"])
            s.text(x, yend + 19, lab, 11, t["muted"], anchor="middle")
        for k, (key, who, val) in enumerate((("s1", "Sea", r["sea_wall"]),
                                             ("s2", "MATLAB", r["ml_wall"]))):
            y = yb + k * (bar_h + 8.0)
            s.text(px, y + bar_h - 4, who, 12, t["ink2"])
            s.hbar(X(0), X(val), y, bar_h, t[key], "%s %s" % (r["id"], who))
            s.text(X(val) + 6, y + bar_h - 4, "%s s" % report.f3(val), 12, t["ink"])
    bottom = top0 + nrows * ph
    fy = bottom + 14
    f1, f2 = footer_lines(info)
    s.text(GUTTER, fy, f1, 12, t["ink2"])
    s.text(GUTTER, fy + 18, "MATLAB's time is its in-session total_seconds; "
           "Sea's includes process start-up and exit.", 12, t["ink2"])
    s.text(GUTTER, fy + 36, f2, 11, t["muted"])
    height = int(fy + 36 + 18)

    title = "Whole-process time: Sea vs MATLAB (lower is better)"
    desc = ("Whole-process seconds per workload, best of %d runs, each workload on its own "
            "scale. " % info["reps"] +
            "; ".join("%s: Sea %s s, MATLAB %s s" % (r["name"], report.f3(r["sea_wall"]),
                                                     report.f3(r["ml_wall"])) for r in rows) +
            ". " + f1 + " " + f2)
    return s.finish(height, title, desc, ident)


# ---------------------------------------------------------------------------------------

def main(argv):
    if len(argv) != 2 or any(a.startswith("-") for a in argv):
        sys.stderr.write("charts: usage: charts.py DIR OUTDIR\n")
        return 2
    dirpath, outdir = argv
    try:
        rows, info = load(dirpath)
        files = []
        for theme in ("light", "dark"):
            files.append(("speedup-%s.svg" % theme, speedup_svg(rows, info, theme)))
            files.append(("times-%s.svg" % theme, times_svg(rows, info, theme)))
        try:
            os.makedirs(outdir, exist_ok=True)
            for name, text in files:
                with open(os.path.join(outdir, name), "w", encoding="utf-8",
                          newline="\n") as f:
                    f.write(text)
        except OSError as e:
            fail("cannot write into %s: %s" % (outdir, e.strerror or e))
    except report.ReportError as e:
        sys.stderr.write("charts: %s\n" % e)
        return 2
    for name, _ in files:
        sys.stdout.write("charts: wrote %s\n" % os.path.join(outdir, name))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
