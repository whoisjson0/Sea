# Sea — notes for agents

Sea is a fast matrix/numerical language, an alternative to MATLAB, with modern C/Rust-like syntax
(not MATLAB-compatible). Child project of Baysick (https://github.com/frgmt0/Baysick), a Dartmouth
BASIC (1964) rebuild hand-written in assembly, with targets `arm64-macos` (native) and
`x86_64-linux` (cross-compiled, tested on Linux), its own IR and plug-in backends.

## Status
**Phase 0** (agreement and contracts, 2026-10-20) and **phase 1** (scalar core, arm64; complete
at sea commit e6e9873) of DESIGN.md §8 are done. The six passes (`seaparse` `seacheck` `seaexpand`
`sealower` `seaopt` `seagen_a64`), the driver, the arm64 runtime and the tools are written; the
W5 LCG acceptance test passes; the size estimate of DESIGN.md §2.7 is recalibrated from the real
passes. Decisions taken during phase 1 are recorded in DESIGN.md §0 ("Decided in phase 1").
**Phase 2** (the x86_64 target: `seagen_x64`, the x86_64 runtime, `cross*.sh`; DESIGN.md §4.7.1,
§4.9.1, §6.6.1) is complete at sea commit a87ca78: `make cross` passes every case on the Linux
host. Decision 7 (the user's MATLAB rerun) is done: the MATLAB baseline is committed at sea
commit c1736f7. **Phase 3** (elementary functions: Sea's own scalar `log exp sin cos pow hypot`
on both targets (Decision 6), and the compile-time `pow`; DESIGN.md §4.10) is complete at sea commit 98e1e14: the
`math/` tests pass on both targets (≤ 1 ulp against the high-precision references, identical bits
on both targets). **Phase 4** of DESIGN.md §8
(**arrays and structs**) is complete: sub-phases 4a (pass 2a split into `seaname` and `seacheck`,
sea commit 263ee1f), 4b (the phase-4 specification, 2dfe535), 4c (heap runtime, a59ca07) and 4d
(dynamic arrays core, W4 scalar SOR accepted by `make test-accept`) are done. The size gate after
4d (DESIGN.md §2.7) projected `sealower` to 9 665 lines, so sub-phase 4e-0 split pass 3a into
`sealoop` (`sea.hir` → `sea.hirl`, the array constructs made explicit as scalar loops) and
`sealower` (`sea.hirl` → `sea.lir1`, unchanged). **4e-0 is done** (built and tested, no change of
behaviour; Decisions 26–30; measured: `sealoop` 2 323 lines with 7 free array letters, `sealower`
5 164 lines with 4 free, DESIGN.md §2.7); **4e (array expressions) is done** (Decisions 31–37: the `sealoop` rewrites L5–L12 with the
`sea.hirl` refinements R1–R11, rule 27 for fixed-size numeric arrays, DESIGN.md §3.5.9, §3.6.6, §8;
measured: `sealoop` 4 129 lines, `sealower` 5 971, DESIGN.md §2.7); **4f (reductions, sorting,
searching, library options) is done** (Decisions 38–43: the `sealoop` rewrites L13–L14 with the
`sea.hirl` refinements R12–R16 and the `wop` word `and`, result types on fixed-size arguments,
`rt_sort.s` with `f64`, `i64` and `str` on both targets, error 115 for a positional argument after a
named one; DESIGN.md §0, §3.5.9, §4.8, §8). The size gate after 4f (Decision 35) passed with no
split: `sealoop` 4 400 built lines (projected v1 7 950, 4 free array letters), `sealower` 6 087
(7 987, 4 free), `seacheck` 5 830 (6 780, 14 free), DESIGN.md §2.7. **4g** (strings, structs,
records, `match`, `error`, `args`) **is done** (Decisions 44–48 and the lead decisions L-a … L-n:
the `sea.hirl` refinements R17–R25 with no new record kind, the `sealoop` rewrites L15 projection, L16
`match` and L17 reference, aggregate and field-path stores, element-wise `str` operators, scalar-only
`str()`/`lower()`, records as anonymous struct types, the shared module `passes/lib/layout.bas`; no
contract file changes; DESIGN.md §0, §2.6.2, §2.7, §3.5.9, §6.2, §8), built in two sub-steps
(Decision 47). **4g-1** (strings, `match`, `error`, `args`, `str` elements, `sort_str`; lead
decision L-n: an L17 `str` element store into a `ref` parameter root reads P afresh after the cow
until 4g-2). The size gate after 4g-1 passed with no relief: `sealower` 6 349 built lines (projected
after 4g-2 P = 6 956, 44 under 7 000; v1 8 056; 4 free array letters), `sealoop` 4 659 (5 114; 8 214;
4 free), `seacheck` 5 944 (6 081; 14 free), DESIGN.md §2.7. **4g-2** (structs, records, projection,
fixed-size `str` and struct arrays, the module `layout` of 123 lines, `manualD_part1`) measured
`sealower` 6 994 built lines (v1 8 394 with 4h counted, lead decision L-o; 3 free array letters), `sealoop` 5 433 (8 533, 3 free),
`seacheck` 6 424 (14 free), `seaname` 5 262 (DESIGN.md §2.7, "Measured after 4g-2"): `sealower` is
6 lines under its 7 000-line cap. The relief is agreed (Decisions 49–52, lead decisions L-o–L-r, DESIGN.md §0, §2.7, §8, §9): a
behaviour-neutral compaction of `sealower` (C1–C6, about 600 lines; reserves: `sea.hirl` validation
into `seaval`, rule 36's composites into `sealoop`, a middle HIR→HIR pass), the 7 000-line cap kept
through 4h, gates after 4h-0, 4h, phase 6 and phase 8. **4h-0 is done**: `sealower` 6 304 built
lines (690 saved; the multi-line `DEF` functions `FNQ`, `FNE`, `FNR$`; 3 free array letters),
proved neutral by byte-identical `sea.lir1`, and the gate after 4h-0 passed (6 604 ≤ 7 000 with
4h, v1 7 704, stress 8 254; reserve V not needed), DESIGN.md §2.7 "Measured after 4h-0". **4h is
done** (Decisions 53–57, lead decisions L-s–L-ab: prelude inlining by `sealoop`'s rewrite L18 into
the `sea.hirl` records `iblk`/`iret` (`passes.txt` HL 88–89), lowered by `sealower` (R26–R30);
`std.sea`'s `linspace`, `meshgrid`, `setdiff`, `bincount`; W5 accepted). The gate after 4h passed:
`sealower` 6 473 built lines (v1 7 573, stress 8 123; free letters `C S X`), `sealoop` 5 829 (v1
8 429; `B X Y`), `seacheck` 6 426 (14 free), `seaname` 5 281 (DESIGN.md §2.7 "Measured after 4h").
**Phase 4 is complete.** **Phase 5** (scalar code quality) is specified and agreed (5a; Decisions
58–73, lead decisions L-ac–L-at (L-an–L-at after a review of the text): `seaopt`'s T1–T10 of
DESIGN.md §5.8, the shared allocator `passes/lib/ralloc.bas` of §4.9.2, the shape tests and
micro-benchmarks of §6.2, §5.9). **5b** (allocator and code selection, both targets) and **5c-1**
(`seaopt`'s T1–T4, T10) **are done**: `make test` and `make cross` (555) pass; `seaopt` 5 316 built
lines, `seagen_a64` 4 958, `seagen_x64` 5 294 (DESIGN.md §2.7 "Measured after 5b and 5c-1", with the
gate arithmetic that showed `seaopt` could not take T5–T9). The user then decided Decision 74 (the
loop transformations T5–T9 move to a new pass 3c `sealopt`, `sea.lir2` → `sea.lir`, sharing
`seaopt`'s reader, validator, writer and T10 through the shared main-program part `passes/lib/lirrw.bas`, L-bi; phase 7's
vectorizer goes there too, revised by Decision 78) and Decision 75 (the allocator extends an interval over a loop only when
it may be live at the loop's top), lead decisions L-bc–L-bf; after their review, L-bg–L-bk (liveness tested after a loop as
inside it, coverage by effective part, `lirrw` as a main-program part, golden lists, sizes) and
L-bl–L-bp (fresh registers for each copy of a versioned or unswitched loop, T9 placing copy-only
values back into each copy's arm, T10 deleting dead selections, §5.2's register counts re-derived,
`lirrw`'s reserved names: 2 free array letters in `seaopt` and `sealopt`) and L-bq (T4's
self-reading selection only where its register is written on every path or dead). **5c-2 is done** (`sealopt` 5 411 built
lines, `seaopt` 5 491; `make test` and `make cross` (596) pass; lead decisions L-br–L-bv, DESIGN.md
§2.7 "Measured after 5c-2"). **5d is done** (Decisions 76–77, the `seagen_x64` `imulh` fix): the
W5 and W4 loops meet DESIGN.md §5.2's shapes on both targets (20/23 and 24/27 instructions, no
frame access); micro-benchmarks (§5.9): `sor` ≈ C on both targets, `lcg` 1.19× (M2 Pro) and 1.35×
(i7-4790) C. **Phase 5 is complete** (shapes met on both targets, `sor` ≈ C, `lcg` 1.19/1.35× C;
Decisions 76–78): the gate after phase 5 passed with Decision 78 (phase 7's scalar replacement
and vectorization get their own pass 3d after `sealopt`, sharing `lirrw`, name and files at phase
7's spec; `sealopt` takes fixes only, its letter condition waived; DESIGN.md §2.7 "Measured after
5d"). **Phase 6** (functions and output) **is specified** (6a, agreed 2026-10-26: Decisions 80–93,
lead decisions L-bw–L-cx; DESIGN.md §2.11, §2.7, §6.2, §6.3, §8): named and default arguments,
§8.6 inlining (`sealoop` L20, `sealower` R31/R32), elemental functions (L19), `format`, `print`,
`make_dir`, `f64 %`, `write_json` (rule 39, runtime entries 23–38), the W1 and W5 ports without
figures; `seacheck` gated as `sealower` is (Decision 82). **6b is done** (2026-10-28: named and
default arguments, §8.6 inlining, `f64` `%`, `format`, `print`, `make_dir`, runtime entries 23–38;
lead decisions L-cy–L-dh; `make test` and `make cross` (700) pass; `seacheck` 6 798 built lines,
`sealoop` 5 936, `sealower` 6 637, `seaname` 5 424, DESIGN.md §2.7 "Measured after 6b"). **6c is
done** (2026-10-28: elemental functions, `ind2sub` with an array `r`; lead decisions L-di–L-dq;
`make test` and `make cross` (742) pass; `seacheck` 6 863 built lines, `sealoop` 6 438, `seaexpand` 4 359, `seaname` 5 555, DESIGN.md §2.7
"Measured after 6c"; the measurement after 6c calls for no relief, so 6b-0 is not run, Decision 87).
**6d is done** (2026-10-28: `write_json`; lead decisions L-dr–L-ec; `make test` and `make cross`
(776) pass; `seacheck` 6 919 built lines, `seaexpand` 4 796, `sealoop` 6 512, `sealower` 6 729,
DESIGN.md §2.7 "Measured after 6d"). **6e is done** (2026-10-29: the ports `ports/w1_shaft_design.sea`
and `ports/w5_tolerance_mc.sea` without figures, their token maps, `tests/accept.sh`, the cross case
kind `ports`; lead decisions L-ed–L-eg; `tests/accept.sh` passes both, every JSON key and both reports;
`make test` and `make cross` (778) pass, the ports byte-identical on the host but for the `Compute
time` line; DESIGN.md §6.3 "Measured at 6e"). The gate after phase 6 passes every program with no
relief (`sealoop` 6 512 built lines, 8 762 at the stress line with phase 7's fusion, 3 free letters:
fusion stays in `sealoop`; DESIGN.md §2.7 "Measured at the gate after phase 6"). **Phase 6 is
complete.** **Phase 7** (fusion and SIMD, DESIGN.md §8 row 7) **is specified** (7a, agreed
2026-10-29 after two independent reviews: Decisions 94–113, each option (a), lead decisions
L-eh–L-fl; DESIGN.md §2.12, §2.7, §6.2, §6.3, §6.6.1, §8): fusion F1–F5 in a new pass-3a program
`seafuse` (`sea.hir` → `sea.hirf`, ahead of `sealoop`, also doing L19), pass 3d `seavec`
(`sea.lir3` → `sea.lir`: T11 unrolling, T12 scalar replacement, T13 if-conversion and
vectorization), NEON/SSE2/AVX2 code in pass 4, runtime entries 39–50 (vector elementary
functions), the W4 port, a run-time allocation count (`SEA_HEAP_CHECK=count`), and LANGUAGE.md
§9.2's out-of-memory sentence (added by WP-CONTRACT). **7b is done** (2026-10-29: the
contract changes, the new programs `seafuse` and `seavec`, `sealopt` writing `sea.lir3`, L19
rewritten in `seafuse`, `sealoop` reading `sea.hirf`; neutral by Decision 109 over the whole corpus;
lead decisions L-fm–L-fu; `seafuse` 3 164 built lines with 5 free letters, `sealoop` 6 396;
DESIGN.md §2.7 "Measured after 7b"). **7d is done** (2026-10-29: the vector forms of the
elementary functions, entries 39–50, `rt_vmath.s` per runtime; DESIGN.md §2.12.8). **7c is done**
(2026-10-30: fusion F1–F5 in `seafuse`, with buffer reuse, in-place selection stores, `tbind`
groups, fused masked and `.flat` reductions and folded concatenation parts in stacks and mixed
rows; the user's D1–D3 and the concatenation decision, lead decisions L-fv–L-gj, DESIGN.md
§2.12.3, §2.12.4 "Readings fixed by 7c"; `make test` and `make cross` (876) pass; two independent
reviews with differential fuzzing against the pre-7c compiler, every defect fixed; the measurement
after 7c passes with no relief: `seafuse` 6 427 built lines with 5 free letters, `sealoop` 6 431
with 3, DESIGN.md §2.7 "Measured after 7c"). **7e is done**
(2026-10-31: `seavec` with T11 unrolling, T12 scalar replacement and T13 if-conversion and
vectorization, vector code in `seagen_a64` (NEON) and `seagen_x64` (SSE2, AVX2), the vector classes
of `lirrw` and `ralloc`, `tools/lirchk` validating every `sea.lir` (Decision 116), both x86_64
variants in the cross run; Decisions 115–117 decided by the user, lead decisions L-gk–L-hp, DESIGN.md
§2.12.6, §2.12.7, §6.6.1; `make test` passes (stage 1 235, programs 2 191) and `make cross` passes
941 cases (default 822, `sse2` 822, once-only 119, total 1 763); measured: `seavec` 5 825 built
lines, `seagen_a64` 5 254, `seagen_x64` 6 103, all inside the gate, DESIGN.md §2.7 "Measured after
7e"). **7f is done**
(2026-11-01: the W4 port `ports/w4_heat_plate.sea` and its token map, accepted by `tests/accept.sh`;
the allocation count `SEA_HEAP_CHECK=count` in both runtimes; `tests/fusion.sh` (W1 0 and W4 6
allocations per iteration) and the cross case kind `fusion`; the `vector` shape lines with op lists
(Decision 119); T9 restricted to `loop` blocks (Decision 118); the fix of `sealoop`'s and
`seafuse`'s marker reading inside string payloads; Decisions 118–119 decided by the user, lead
decisions L-hq–L-ib, DESIGN.md §2.12.10, §4.5, §6.3, §6.6.1; `make test` passes (stage 1 237,
shape 8, fusion 2, programs 2 192, accept 2 + 3) and `make cross` passes 954 cases (default 826,
`sse2` 826, once-only 128, total 1 780); measured: `seafuse` 6 482 built lines, `sealoop` 6 485,
`sealopt` 5 548, and the gate after phase 7 passes every program with no relief, DESIGN.md §2.7
"Measured at the gate after phase 7"). **7g is done**
(2026-11-01: the W7 port `ports/w7_drivetrain.sea` and its token map, port-only by Decision 120 (the
user), no pass, runtime, prelude, include or golden change; `tests/accept.sh` passes W1, W4, W5 and
W7; lead decisions L-ic–L-ii, DESIGN.md §6.3 "Measured at 7g"; `make test` passes (accept 2 + 4) and
`make cross` passes 955 cases (default 827, `sse2` 827, once-only 128, total 1 782); W7 compiles in
17.4–20.8 s and computes in 0.134–0.135 s). **Phase 7 is complete.** **Phase 8** (linear algebra,
DESIGN.md §8 row 8) **is specified** (8a, agreed 2026-11-01 after one independent review: Decisions
121–129, each option (a), lead decisions L-ij–L-jf; DESIGN.md §2.13, §8 rows 8a–8d, §9): `@`
(Baysick's GEMM for matrix @ matrix, Sea's class-E GEMV and 8-lane vector @ matrix kernels, fixed-size
`@` inlined by `sealoop`'s L21), the handles `Lu`/`Chol`, `lu chol solve rcond eig_sym` as runtime
entries 51–61 (blocked LU and Cholesky through `_bsk_kern_gemm_sub`, `dgecon`-style `rcond`, tred1 +
tql1), the W2 and W3 ports. **8b is done** (2026-11-01: WP-CONTRACT's `rt.inc` entries 51–61 and
constants with LANGUAGE.md's agreed text; `@` of every numeric operand pair: `seacheck`'s `ckmm`
(`cvt`, `dyn`, 217), `sealoop`'s R35 and L21 in the new part `lpbmat.bas`, `sealower`'s rule-39 rows
`MATMUL`/`GEMV`/`VECMAT`; `rt_gemm.s` (GEMM through Baysick, GEMV and VECMAT in NEON, SSE2 and AVX2
forms, class E) and `rt_kern.s` (`_sea_variant`) in both runtimes; `tests/la/` with the group
`test-la` and the cross cases `la/la_check`, `la/la_link`; 22 `la_*` programs, `r_la_*`/`err_la_*`
errors, `la8_mm_*` and `la8_l21_*` dumps, 8 `rt_la_gemm_*` cases per target, `err_ns_matmul`
retired; a review defect fixed (L21 now builds the dynamic vector result of a k = 0 product over 256
elements); `make test` and `make cross` pass (997 cases: default 859, `sse2` 859, once-only 138,
total 1 856); lead decisions L-jg–L-jl; measured: `seacheck` 6 969 built lines, `sealoop` 6 643,
`sealower` 6 798, DESIGN.md §2.7 "Measured after 8b"). The Baysick-repo work package WP-BSK-OVERLAP
(Baysick DESIGN.md §6.6.1: "overlap" means sharing an element, plus a `kern_check` case) has landed
(Baysick commit 8c8dee3). **8c is done** (2026-11-01: the handle types `Lu` and `Chol` and `lu chol
solve rcond eig_sym` through `seaname`, `seacheck`, `sealoop` (R35) and `sealower` (the eight
remaining rule-39 rows); `rt_lu.s` (blocked LU and Cholesky through `_bsk_kern_gemm_sub`, the
solves, `SOLVE`, `RCOND`, the private `sea_la_potrf`/`sea_la_issym`) and `rt_eig.s` (tred1 + tql1,
the generalized form) in both runtimes, `sea_free`'s handle branch; Decision 130 (the user: `rcond`
is 0 as soon as an estimator solve overflows); 23 `la_lu/chol/solve/eig_*` programs, 26 `r_la_*`
and 14 compile errors, `la8_lib_*` dumps, `rt_la_*` cases (rt 171 on arm64, 173 on x86_64),
`la_check` 31 042 cases on the Mac and 62 084 on Linux, the one-time SciPy check of the RCOND
transcription (PASS), `err_ns_lib_solve` retired; an integration defect fixed (`sealower`'s reading
check reused the constants E7/E8 as scratch); `make test` and `make cross` pass (1 087 cases: default
911, `sse2` 911, once-only 176, total 1 998); lead decisions L-jm–L-jv; measured: `seaname` 5 625
built lines, `seacheck` 7 059, `sealoop` 6 689, `sealower` 6 841, no relief, DESIGN.md §2.7
"Measured after 8c"). **8d is done** (2026-11-02: the ports `ports/w2_truss_fem.sea` and
`ports/w3_quarter_car.sea` and their token maps, port-only with no compiler or runtime defect found;
`tests/accept.sh` passes W1, W2, W3, W4, W5 and W7 (W2's float keys within 6.4e-11 relative, `r_worst`
59 against MATLAB's 61 by the near-tie rule; W3's 27 keys, largest relative difference 9.6e-16);
Decision 127's cross rule: the `// cross: compare=accept [except=…]` header line, deferred runs on
the host (`cross_run.sh -k DIR`), the return path `#sea-cross-files N` and the Mac-side
`tests/cross_accept.sh`; lead decisions L-jw–L-kd, DESIGN.md §2.13.9, §6.3 "Measured at 8d", §6.6.1
"As built in 8d"; `make test` passes (accept 2 + 6) and `make cross` passes 1 089 cases (default 911,
`sse2` 911, once-only 176; host 1 998 passed, 0 failed, 4 deferred; Mac 4 passed, 0 failed); W2
compiles in 17.83–17.99 s (warm) and computes in 0.495–0.504 s, W3 in 5.73–5.84 s and 0.067–0.068 s; the gate
after phase 8 passes every program with no relief, DESIGN.md §2.7 "Measured at the gate after phase
8"). **Phase 8 is complete.** **Phase 9** (plotting, DESIGN.md §8 row 9) **is specified** (9a, agreed
2026-11-02 after one independent review: Decisions 131–142, each the recommended option (133 (b),
the others (a)), lead decisions L-ke–L-lf; DESIGN.md §2.14, §8 rows 9a–9d, §9): the `Figure`/`Axes`
objects, the 21 plotting calls as runtime entries 62–82, the SVG writer, contours, embedded PNG
images, the six ports' figures. **9b is done** (2026-11-03: WP-CONTRACT's `rt.inc` entries 62–82,
`errors.inc` codes 22–29 and the two plot limits; the 21 plotting calls and the handle types
`Figure`/`Axes` through `seaname`, `seacheck` (the new part `sc9plot.bas`: options, defaults,
overloads, the written form), `sealoop` (R36) and `sealower` (rule 39's 21 rows), the phase rule
gone (259 unreachable); `rt_plot.s` (objects, layout, limits and ticks, the SVG writer of lines,
markers, reference lines, legends and twins; 3 656 lines on arm64, 3 618 on x86_64),
`_sea_fmt_num`, `_sea_file_put` and `sea_free`'s `Figure`/`Axes` branches in both runtimes; a
pre-existing `cty` defect fixed; 26 `tests/plots/` programs checked by `tests/plots.sh` and
`tests/plot_struct.py` (`make test-plots`, needs `uv`) and byte-identical in the cross case kind
`plots/`, 34 `r_plot_*` and 12 `err_plot_*` errors, `plot9_*` dumps, rt 229 cases on arm64 and 211
on x86_64; `make test` passes (stage 1 331, programs 2 425, plots 26, accept 2 + 6) and `make cross`
passes 1 194 cases (default 978, `sse2` 978, once-only 214; host 2 170 passed, 0 failed, 4
deferred; Mac 4 passed, 0 failed); lead decisions L-lg–L-lq; measured: `seacheck` 7 335 built lines, `sealoop` 6 715,
`sealower` 6 885, no relief, DESIGN.md §2.7 "Measured after 9b"). **9c is done** (2026-11-03: bars, contours,
images and PNG: `rt_plot2.s` (`BAR`, `BARH`, `CONTOUR`, `IMAGE`, marching squares, the colour map,
the colorbar) and `rt_png.s` (PNG with stored deflate, CRC-32, Adler-32, base64) in both runtimes,
`rt_plot.s`'s dispatch of series kinds 3–6; runtime sizes 6 287 lines on arm64 and 6 127 on x86_64,
above the estimates, DESIGN.md §2.7 "Runtime sizes at 9c"; one independent review, no runtime
defect; 8 more `tests/plots/` programs (34), 16 more `r_plot_*` errors, `plot9_cases.py`'s 9c part,
the `.struct` keys `clabel`, `segment` and `pixels`, rt 256 cases on arm64 and 228 on x86_64;
`make test` passes (programs 2 441, plots 34) and `make cross` passes 1 235 cases (default
1 002, `sse2` 1 002, once-only 231; host 2 235 passed, 0 failed, 4 deferred; Mac 4 passed, 0
failed); lead decisions L-lr–L-lz). **9d is done** (2026-11-03: the six ports' `--figures` blocks
and their `ports/NAME.struct` files; `tests/accept.sh` runs each port once with `--export-reference
--figures` and checks the run directory and `plot_struct.py`; the cross case kind `ports` packs the
SVGs, `cross_accept.sh` compares W3's byte for byte and W2's by Decision 138 (a) through the new
`tests/svg_skeleton.py` (header key `svg=approx`); the `vector` shape lines moved to W1 259–265 and
W4 296; port-only, no pass or runtime change; `make test` passes (programs 2 441, plots 34, accept
2 + 6) and `make cross` passes 1 235 cases (default 1 002, `sse2` 1 002, once-only 231; host 2 235
passed, 0 failed, 4 deferred; Mac 4 passed, 0 failed); lead decisions L-ma–L-md; DESIGN.md §6.3
"Measured at 9d"; the gate after phase 9 passes every program with no relief, §2.7 "Measured at the
gate after phase 9"). **Phase 9 is complete.** **Phase L** (text library, DESIGN.md §8 row L) **is
specified** (La, agreed 2026-11-03 after one independent review: Decisions 143–149 each option
(a), Decision 150 (the user's rulings: blanks and `0x` rejected by the parse functions, `shl` drops
bits, `+`/space ignored with `%x`), lead decisions L-me–L-mx; DESIGN.md §2.15, §8 rows La–Lc, §9):
`read_lines`, `split`, `substr`, `parse_i64`/`parse_f64`, the bitwise functions `bitand bitor
bitxor bitnot shl shr sar`, `%x`/`%X`, runtime entries 83–87, errors 30–35. **Lb is done**
(2026-11-04: the contract (errors 30–35, entries 83–87, `enum conv x X`, LANGUAGE.md amended,
§3.4.1's `split` renamed `parts`); the twelve names through `seaname`, `seacheck` (bitwise in
class 2, the text calls as classes 53–57 in `sc9plot.bas`, `%x`), `seafuse` (`shl shr sar` among
the calls with a run-time check, so they fuse only as a root, lead decision L-my), `sealoop`
(`K4$`, R37 no code) and `sealower` (rule 40, rule 39's five rows); the other passes and both code
generators unchanged; `%x`/`%X` in `rt_fmt.s` of both runtimes; the rt `NAME.files/` sidecar in
the runners and the cross scripts; the text calls compile and are dumped but their programs are
not run until Lc; `make test` passes (rt 258, stage 1 354, programs 2 498, plots 34, accept 2 + 6,
`lib_check` 366) and `make cross` passes 1 250 cases (default 1 015, `sse2` 1 015, once-only 233;
host 2 263 passed, 0 failed, 4 deferred; Mac 4 passed, 0 failed); measured: `seacheck` 7 360 built
lines, `sealoop` 6 721, `sealower` 6 943, no relief, DESIGN.md §2.7 "Measured after Lb"). **Lc is
done** (2026-11-04: the text runtime in both runtimes, `rt_text.s` (`SPLIT`, `PARSE_I64`,
`PARSE_F64`, `SUBSTR`; 500 lines on arm64, 596 on x86_64), `READ_LINES` in `rt_file.s` and the
exported `_sea_str_make` in `rt_str.s` (about 741 and 896 lines added), no pass, contract file or
code generator changed; `parse_f64` is one correctly rounded `strtod`, confirmed against Python's
`float()` on both hosts (L-mj); the generator `tests/vectors/libL_cases.py` with its known-answer
files, 391 rt cases per target, the programs `lib_read_lines_*`, `lib_split`, `lib_substr`,
`lib_parse_*` (two known-answer programs of 416 and 187 texts) and `lib_candump`, 25 more
`r_lib_*` errors, 47 rt tests on arm64 and 52 on x86_64; not tested: the `ARRAY_SIZE` and line-length
`OUT_OF_MEMORY` of `READ_LINES` (files over 2 GiB), the capacity-above-2⁶² branch, the `strtod`
`end` guard, and on arm64 the `_sea_alloc` out-of-memory paths; stack depths in DESIGN.md §4.8
(deepest `PARSE_F64`, 1 344 bytes on arm64, 1 592 on x86_64); `make test` passes (rt 305, stage 1
354, programs 2 536, plots 34, accept 2 + 6, `lib_check` 366) and `make cross` passes 1 340 cases
(default 1 053, `sse2` 1 053, once-only 285; host 2 391 passed, 0 failed, 4 deferred; Mac 4
passed, 0 failed); lead decisions L-mz–L-ne; the gate after phase L passes every program with no
relief, DESIGN.md §2.7 "Measured at the gate after phase L"). **Phase L is complete.**
**W8a agreed; W8b done** (2026-11-04, revised after one independent review; DESIGN.md §2.16, §8
rows W8a–W8d: the workload W8 `w8_ev_can`, an ESP32 controller sketch simulated on the host,
writing a CAN log that a Sea port reads, decodes and plots; Decisions 151–160 each decided by the
user as option (a), lead decisions L-nf–L-ny agreed; W8 joins the acceptance set, now seven
workloads). W8c done (2026-11-04); W8d done (2026-11-04); **W8 is complete** (accepted on both
targets). **Phase 10** (benchmarks) **is specified** (10a, agreed 2026-11-04 after one independent
review: Decisions 162–172 each option (a), lead decisions L-ow–L-qa; DESIGN.md §2.17, §8 rows
10a–10d, 10o); next 10b. `make test` passes (rt 305, stage 1 354, programs 2 536, plots
34, accept 2 + 7, `lib_check` 366) and `make cross` passes 1 341 cases (default 1 054, `sse2` 1 054,
once-only 285; host 2 393 passed, 0 failed, 4 deferred; Mac 4 passed, 0 failed).

Versions 0.y.z are alpha; 1.0.0 = v1
(Decision 79).

## Read first
- `docs/LANGUAGE.md` — what Sea programs mean (syntax, types, library, output bytes, errors,
  exit statuses). Normative.
- `docs/DESIGN.md` — goals and their measurement, compiler passes and driver, intermediate file
  formats (§3), runtime ABI, performance model, tests, Baysick growth, milestones, decisions.
  Normative.
- `include/` — the contract files: `passes.txt` (record formats of every intermediate file),
  `limits.inc` (limits), `errors.inc` (error texts and codes, exit statuses) and `rt.inc`
  (runtime layouts and symbols).
- Baysick's `CLAUDE.md` and `docs/` (the toolchain Sea is written in).

## Commands
- Build: `make` (= `make all`: runtime, tools, passes, install). Each pass is built as
  `build/gen/<pass>.bas` (its own files, the modules and `DATA` blocks of its `build.list`,
  `99999 END`; DESIGN.md §2.6.3) and compiled with Baysick (`BAYSICK=<dir>`, default `..`; run
  `make` there first). `build/` is the installation directory (DESIGN.md §2.10).
- Use the compiler: `build/sea build <file.sea> [-o out] [-S] [--emit ast|res|hir1|hir|hirf|hirl|lir1|lir2|lir3|lir]
  [--no-prelude] [--keep-temps]`, `build/sea run <file.sea> [-- args…]` (DESIGN.md §2.2).
- Tests: `make test` runs, after `make all` and `make check-contracts`, every group even if one
  fails: `test-driver` (`tests/driver_check.sh`), `check-data` (`tests/check_data.sh`, the DATA
  generator), `test-lib` (`tests/lib_check.sh`), `test-arith` (`tests/arith_check.sh`, the exact
  arithmetic modules), `test-rt` (`tests/rt/`, runtime tests against `libsea.a`), `test-stage`
  (`tests/stage.sh`, each pass on the previous pass's golden), `test-shape` (`tests/shape.sh`, the
  instruction-count shape of the W5 and W4 hot loops on both targets, DESIGN.md §5.2, §6.2, and the `vector` lines of W1's bisection and W4's selection store, §2.12.10), `test-fusion` (`tests/fusion.sh`, the allocations per iteration of `tests/fusion/` under `SEA_HEAP_CHECK=count`, DESIGN.md §2.12.10), `test-protocol`
  (`tests/protocol.sh`, truncated input, missing `#end`), `test-math`
  (`tests/math/math_check.c`, all six elementary functions bit for bit over `tests/math/*.vec`, and their vector entries against the scalar ones in every lane position and on random inputs),
  `test-la` (`tests/la/la_check.c`, GEMV and VECMAT bit for bit against the pinned orders,
  MATMUL on exact data, and LU, CHOL, the solves, RCOND and EIG (DESIGN.md §2.13.8) under every
  usable variant, with the header `tests/la/gen_consts.sh` writes;
  then `tests/la/la_link.sh`, the link map; DESIGN.md §2.13.8), `test-programs` (`sh tests/run.sh [-v] [pattern]`: programs/, errors/ and the passes/ dumps), `test-plots` (`sh tests/plots.sh [-v] [pattern]`: the `tests/plots/` programs run under the heap check, then `tests/plot_struct.py` on each `NAME.struct`; needs `uv`; DESIGN.md §2.14.8), `test-accept` (`tests/accept4.sh` then `tests/accept.sh`: the phase-4 acceptance programs and the ports W1, W2, W3, W4, W5, W7 and W8 against `compare.py` and `compare_report.py`, and with `--figures` against `plot_struct.py` and each `ports/NAME.struct`; needs `uv`). Each group is also its own target.
- Math: `make test-math` (part of `make test`; `xcrun cc -O1 -ffp-contract=off` against
  `build/libsea.a`); `make math-tables` (developer check, not in `make test`: `timeout 120 uv run
  --with mpmath python tools/math_tables.py --check`); `uv run --with mpmath python tests/vectors/math_vectors.py --check-format` checks the vector files.
- Size: `make lines` (built lines per pass) and `make check-limits` (lines, `FOR`s, string
  bytes, 255-byte lines against Baysick's limits).
- Include check (Mac, Apple `as`): `make check-includes` — first `make check-contracts`, then
  Sea's `include/*.inc` assembled after Baysick's `include/limits.inc` and `include/runtime.inc`
  (`BAYSICK=<dir>`, default `..`), with the assertions of `tests/include_asserts.inc`.
- Contract drift check: `make check-contracts` (`sh tests/check_contracts.sh`, sh + awk, no
  Python) — every `SEA_*` name and value, error and errno record of `include/*.inc` and every
  record format of `include/passes.txt` equals the tables of `docs/DESIGN.md`, both ways.
- Include check on the Linux host (GNU `as`): `make cross-includes` / `sh tests/cross_includes.sh
  [-H host] [-B baysick_dir]` (ssh host, default `desktop`); on Linux itself:
  `make -f Makefile.linux check-includes`.
- x86_64 cross test (DESIGN.md §6.6.1): `make cross` / `sh tests/cross.sh [-v] [-H host]
  [pattern]` (packs on the Mac, one ssh to the host, default `$SEA_CROSS_HOST` else `desktop`);
  `make cross-pack` builds `build/x86_64-linux-bundle` only (every case runs under both x86_64
  variants, default and `sse2`, unless `SEA_KERNELS` is set); on Linux: `sh tests/cross_run.sh
  [-v] [-k DIR] BUNDLE_DIR` (`-k DIR` keeps the deferred port runs, below; without it they go to a
  printed temporary directory), `make -f Makefile.linux` (`build-x86_64-linux/libsea.a`), `make -f
  Makefile.linux test-rt` (`tests/rt/x86_64_linux/`), `make -f Makefile.linux test-math`. `make cross` also
  runs the once-only cases `math/math_check`, `la/la_check` and `la/la_link` on the host, and the
  case kind `fusion` (`tests/fusion/`, DESIGN.md §6.6.1) under both variants; `make -f
  Makefile.linux test-la` runs `la_check` there. A port with the header line `// cross:
  compare=accept [except=KEY,…]` (W2, W3; Decision 127) is run on the host under both variants but
  deferred (`DEFER ports/NAME (VARIANT)`, its output and JSON kept and sent back after the line
  `#sea-cross-files N` as base64 tar); `tests/cross_accept.sh` judges the kept runs on the Mac
  (`compare.py`, `compare_report.py`, byte equality outside the excepted keys, and the kept SVG:
  byte for byte, or with the header's ` svg=approx` (W2) `plot_struct.py` and `tests/svg_skeleton.py`;
  needs `uv`), and
  `make cross` ends with `host: P passed, F failed, D deferred; Mac: P2 passed, F2 failed`
  (DESIGN.md §2.13.9, §6.6.1).
- W8 (DESIGN.md §2.16.5–§2.16.7; Mac only, developer targets, never part of `make test` or
  `make cross`, L-nx): `make w8-sim` builds the host simulator `build/w8/w8sim` (`xcrun c++
  -std=c++20 -O2 … -Werror`) from `workloads/w8_ev_can/host/` and the unmodified sketch;
  `make w8-log` builds it twice (`-O2`, and `-O0` with the undefined-behaviour and address
  sanitizers), runs the car run and the bench run with each, `cmp`s against the committed
  `workloads/w8_ev_can/w8_ev_can.log`, `serial.txt` and `bench_serial.txt`, and runs the
  floating-point checks; `make w8-log-update` overwrites those three files (only with the user's
  agreement: a new log needs a new MATLAB run); `make w8-sketch` is the `arduino-cli compile`
  check for `esp32:esp32:esp32` (no warning in the sketch or `w8_can_msgs.h`; no upload).
- Benchmarks (DESIGN.md §2.17; Mac; each target depends on `all`; none is part of `make test`,
  `make cross` or any other target): `make bench` = `bench-session` (`bench/session.sh`),
  `bench-build` (`bench/workloads.sh build`, `bench/kernels.sh build`, `bench/micro.sh --current
  build`), `bench-workloads`, `bench-kernels`, `bench-micro`, `bench-numpy` (each `… measure`,
  after the start condition `bench/settle.sh` in final mode), then `bench-check` (`bench/check.py`
  into `$(BENCH_OUT)/check.txt`, the checker's exit status; skipped with `BENCH_QUICK=1`);
  `make bench-cross` (`workloads.sh --cross`, `kernels.sh --cross`, `micro.sh --current --cross`
  on the host into the same session; `BENCH_CROSS_ARGS='-H HOST'`), `make bench-report`
  (`bench/report.py`, the Markdown of `docs/BENCH.md`), `make bench-selftest`
  (`bench/spawn_test.sh` and `check.py --self-test`). Variables: `BENCH_OUT` (default
  `bench/results/p10`; passed as `--out`), `BENCH_QUICK=1` (passes `--quick`: a smoke run whose
  records say `mode quick`, refused by `check.py`). Final mode (no `--quick`) refuses an existing
  result file, a non-empty session directory, a niced driver, battery or Low Power Mode, a dirty
  Sea or Baysick tree (`bench/results` excluded), the `PORTS`/`KERNELS` overrides and a second
  attempt of a tool in one session (`DIR/.attempt-<tool>-<target>`); every `measure`/`--cross`
  refuses a stale build (`bench/stamp.sh` differs from `build/bench/<tool>/stamp.txt`), and a
  quick run refuses a directory holding a final session; trial runs
  go into a scratch `BENCH_OUT`, never `bench/results/`. Python tools via `uv` only; NumPy pinned
  `numpy==2.5.4`.
- Never set a bogus `SDKROOT`/`DEVELOPER_DIR` on the Mac. Python, if ever needed, via `uv` only.

## Repo layout (DESIGN.md §2.10)
- `passes/<pass>/` the Baysick files and `build.list` of each pass (`seaparse seaname seacheck seaexpand seafuse sealoop sealower seaopt sealopt seavec seagen_a64 seagen_x64`); `passes/lib/` the shared modules
  (`io diag tables lirrw limb f64emu fltlit layout ralloc`), interfaces in `passes/lib/API.md`, `API-arith.md`.
- `tools/` `gendata.bas` (the `DATA` generator), `lirchk.bas` (validator of `sea.lir` with the vector classes, run by `tests/run.sh`, `tests/stage.sh` and `tests/cross_pack.sh`), `seaval.bas` (intermediate-file validator: formats `ast res hir1 hir hirf hirl lir1 lir2 lir3 lir`; `lir2` and `lir3` checked as `lir1` except its two lir1-only label rules, L-bu; `hirf` as `hirl` without `inst emap cdat iblk iret`),
  `passlines.sh`.
- `driver/sea` the driver (POSIX sh); `runtime/arm64_macos/`, `runtime/x86_64_linux/` the
  runtimes (`libsea.a`); `std/std.sea` the prelude.
- `tests/` programs/, errors/, passes/ (dump goldens), rt/, shape/, fusion/, la/, harness/, vectors/ and the
  scripts above; `tests/CORPUS.md` describes the corpus.

## Pass authors
- Baysick limits bite: 10 000 stored lines per built program (own files + modules + `DATA`), 255
  bytes per line, 1000 `FOR`s, 1024 active `CALL`s, 65 536 bytes of string constants outside
  `DATA`; numbers are doubles with no ∞, NaN or −0 (use `limb`/`f64emu`, DESIGN.md §2.8); string
  `=` ignores trailing blanks (compare lengths first, DESIGN.md §2.7).
- Edit the numbered `.bas` files directly and keep the numbering stable (insert between existing
  numbers; each part keeps its line range, DESIGN.md §2.6.3).
- When `make check-limits` shows a pass above 9 000 lines, split it into two programs with an
  intermediate file (DESIGN.md §2.7, §7.3) before adding more.

## Goals, in priority order
1. Raw speed: ahead-of-time compiled to native code; fused element-wise expressions without
   temporaries; hand-written SIMD kernels (NEON on arm64, SSE2/AVX2 on x86_64) chosen by
   CPU-feature dispatch; benchmarked honestly against Apple Accelerate and OpenBLAS (the measuring
   bar, not dependencies).
2. A cleaner language than MATLAB.
3. Free, tiny and portable: standalone native binaries, no giant runtime.

## Repo layout
Sea is its own repo and is a git submodule of the Baysick repo at `sea/`. Baysick is the
authority on the toolchain Sea is built with.

## Invariants
- **Sea is written in Baysick.** If Sea needs a language feature Baysick lacks, add it to Baysick
  (in its repo) rather than working around it in Sea. Prefer following later Dartmouth editions;
  Baysick implements Editions 2-6 plus extensions (v0.6.0).
- **Design before code.** Sea's design is agreed (`docs/LANGUAGE.md`, `docs/DESIGN.md`).
  Changes to it are made in those documents together with the user's agreement, before the code
  that depends on them.
- **Contract rule:** a layout, code, limit, symbol or record format shared between separately
  written parts (passes, runtimes, tests) changes only by editing its contract file
  (`include/*.inc` or `include/passes.txt`) AND the matching doc section in the same change.
  Never hard-code a value that has a name in a contract file.
- **Performance claims need benchmarks** with stated methodology (hardware, sizes, baselines,
  how timed). No claim without a measurement behind it.
- **Follow Baysick's workflow:** spec/contract first (normative docs, shared contract files), then
  implementation, then tests. Expected test outputs come from the spec, never from what the
  implementation prints. See Baysick's `CLAUDE.md` and `docs/`.
- No TODOs, stubs, placeholder or fake data.
- Do not add a license or badges until the user decides on them.
