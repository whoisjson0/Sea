# Sea -- build and checks on the Mac (arm64-macos), docs/DESIGN.md 2.6.3, 2.10, 6.
#
#   make                  = make all
#   make all              build/ = the installation directory (DESIGN.md 2.10): runtime, tools,
#                         every pass that is written, and the install step. A part that is not
#                         written yet is reported ("make: ... not written yet"), not hidden,
#                         and does not stop the parts that exist.
#   make runtime          build/libsea.a from runtime/arm64_macos/*.s
#   make tools            build/tools/gendata, build/tools/seaval, build/tools/lirchk from tools/*.bas
#   make passes           build/<pass> for each of seaparse seaname seacheck seaexpand seafuse sealoop sealower seaopt sealopt seavec
#                         seagen_a64: build/gen/<pass>.bas (passes/<pass>/*.bas, then the modules
#                         and DATA blocks of passes/<pass>/build.list, then 99999 END; DESIGN.md
#                         2.6.3), compiled with $(BAYSICK)/build/baysick
#   make install          build/sea (the driver), build/std.sea, build/errors.inc,
#                         build/limits.inc, build/libbaysickrt.a (copied from Baysick's build)
#   make test             all, then every test group below that has its script; fails if any fails
#   make test-programs    tests/run.sh      programs/ and errors/ (built passes, end to end)
#   make test-plots       tests/plots.sh    the plot programs of tests/plots/: run, heap check, then
#                         tests/plot_struct.py on NAME.struct (DESIGN.md 2.14.8; needs uv)
#   make test-rt          tests/rt/run_rt.sh  runtime tests (assembly programs against libsea.a)
#   make test-stage       tests/stage.sh    each pass on the golden output of the previous one
#   make test-shape       tests/shape.sh    instruction-count shape of the W5 and W4 hot loops, both targets (5.2)
#   make test-fusion      tests/fusion.sh   allocations per iteration of W1's grid bisection and W4's red-black
#                         iteration under SEA_HEAP_CHECK=count (2.12.10, the temporaries check)
#   make test-accept      tests/accept4.sh  phase-4 acceptance programs against compare.py --keys (needs uv)
#                         then tests/accept.sh: the ports W1, W2, W3, W4, W5 and W7 (compare.py,
#                         compare_report.py, and with --figures plot_struct.py on ports/NAME.struct)
#   make test-protocol    tests/protocol.sh pass protocol: missing #end, driver #end check
#   make test-driver      tests/driver_check.sh  the driver without passes
#   make test-lib         tests/lib_check.sh    the shared pass modules
#   make test-arith       tests/arith_check.sh  the exact-arithmetic modules
#   make test-math        tests/math/math_check.c (xcrun cc) against build/libsea.a and
#                         tests/math/*.vec: log exp sin cos pow hypot, bit for bit (4.10.6), and the
#                         vector entries sea_*_x in every lane position and on 2^24 random calls per
#                         lane pattern (2.12.8)
#   make test-la          the linear-algebra checks (DESIGN.md 2.13.8): tests/la/la_check.c (xcrun cc,
#                         -I the directory of the generated sea_consts.h) against build/libsea.a and
#                         build/libbaysickrt.a, every usable kernel variant (GEMV, VECMAT bit for bit
#                         against the pinned orders, MATMUL on exact data), then tests/la/la_link.sh
#                         (the link map of tests/programs/la_mm_exact.sea names only rt_kinit.o and
#                         rt_k*.o among libbaysickrt.a's members, L-ja)
#   build/obj/la/sea_consts.h  the C header of the contract constants, written by
#                         tests/la/gen_consts.sh from include/rt.inc, limits.inc, errors.inc (L-jd)
#   make math-tables      uv run tools/math_tables.py --check (timeout 120): the committed
#                         include/math_tables.inc equals its definitions; developer tool,
#                         not part of make test
#   make check-data       tests/check_data.sh   the DATA generator on the contract files
#   make lines            line count of each built pass vs Baysick's LIM_LINES
#   make check-limits     lines, FOR statements, string-constant bytes, 255-byte lines
#   make check-includes   first make check-contracts, then assemble the contract
#                         include files (include/*.inc) with Apple as: layout
#                         assertions, code ranges, table sizes, and no name clash
#                         with Baysick's include/limits.inc and include/runtime.inc
#   make check-contracts  the drift check (tests/check_contracts.sh, sh + awk):
#                         every SEA_* name and value, error and errno record of
#                         include/*.inc and every record format of
#                         include/passes.txt equals the tables of docs/DESIGN.md
#                         (2.6.1, 2.6.2, 3, 4.8), and vice versa
#   make cross-pack       pack the x86_64-linux test bundle into build/x86_64-linux-bundle
#   make cross            pack, run on the Linux host (HOST=... or SEA_CROSS_HOST, default desktop), report
#   make cross-includes   the same check with GNU as on the Linux host
#                         (tests/cross_includes.sh; HOST=... to override)
#   make clean            remove build/
#   make w8-sim           build/w8/w8sim, the W8 host simulator (DESIGN.md 2.16.5-2.16.7; xcrun c++)
#   make w8-log           build w8sim twice (-O2, and -O0 with the sanitizers), run the car and the
#                         bench run with each, cmp against the committed w8_ev_can.log, serial.txt
#                         and bench_serial.txt, and run the floating-point checks (2.16.7)
#   make w8-log-update    the same builds and checks, then overwrite the three committed files
#                         (only with the user's agreement after W8b: a new log needs a new MATLAB run)
#   make w8-sketch        arduino-cli compile of the sketch for esp32:esp32:esp32, no warning in it
#                         (none of the w8-* targets is part of make test or make cross, L-nx)
#
# Benchmarks (DESIGN.md 2.17.9; Mac; each depends on all; none is part of make test, make cross or
# any other target). BENCH_OUT is the results directory (default bench/results/p10, relative to
# this repository; passed as --out), BENCH_QUICK=1 passes --quick (a smoke run whose records say
# mode quick, which bench/check.py refuses), BENCH_CROSS_ARGS passes -H HOST to the --cross runs:
#   make bench-session    sh bench/session.sh $(BENCH_OUT): the session id (2.17.3, L-ps)
#   make bench-build      sh bench/workloads.sh build, sh bench/kernels.sh build,
#                         sh bench/micro.sh --current build (no measurement)
#   make bench-workloads  sh bench/workloads.sh measure (2.17.4)
#   make bench-kernels    sh bench/kernels.sh measure (2.17.6)
#   make bench-micro      sh bench/micro.sh --current measure (2.17.7)
#   make bench-numpy      sh bench/numpy.sh measure (2.17.5)
#   make bench-check      uv run bench/check.py $(BENCH_OUT) into $(BENCH_OUT)/check.txt, then the
#                         file printed; the checker's exit status, and no check.txt after a setup
#                         error (2.17.8)
#   make bench            bench-session, bench-build, bench-workloads, bench-kernels, bench-micro,
#                         bench-numpy (L-pl), then, in final mode only, bench-check
#   make bench-cross      sh bench/workloads.sh --cross, sh bench/kernels.sh --cross,
#                         sh bench/micro.sh --current --cross, into the session of $(BENCH_OUT)
#   make bench-report     uv run bench/report.py $(BENCH_OUT): the Markdown of docs/BENCH.md
#   make bench-charts     uv run bench/charts.py $(BENCH_OUT) docs/img: the README's SVG charts,
#                         speedup-{light,dark}.svg and times-{light,dark}.svg (deterministic)
#   make bench-selftest   sh bench/spawn_test.sh and uv run bench/check.py --self-test
#
# BAYSICK is the Baysick checkout (default: the parent repository, Sea being its submodule
# at sea/); its build/baysick and build/libbaysickrt.a must exist for the passes (run make
# there first). The include check works in a temporary directory and leaves no files behind.
#
# Per-pass build list, passes/<pass>/build.list (one file per pass; '#' starts a comment):
#   lib <module>...    shared modules of passes/lib/: io diag tables lirrw limb f64emu fltlit layout ralloc
#                      (lirrw, the shared main-program part of the LIR passes, overlaps the lines of limb
#                      and f64emu: a list naming it with either is a build error, DESIGN.md 2.6.3, L-bi)
#   data <block>...    generated DATA blocks: errors errno exits consts entries records mtab
# The parts are concatenated in the canonical order of DESIGN.md 2.6.3 whatever the order
# written; an unknown name is a build error.
#
# tools/gendata is run in include/ (it opens limits.inc errors.inc rt.inc passes.txt math_tables.inc by fixed
# names) with the block names, canonical order, one per line, on standard input; the DATA lines,
# numbered from 89000, are its standard output.

AS      := as
BAYSICK ?= ..
# The ssh host: HOST=... on the command line, else $(SEA_CROSS_HOST), else desktop (a stray
# exported HOST of csh-family shells is deliberately ignored).
ifeq ($(origin HOST),command line)
CROSS_HOST := $(HOST)
else
CROSS_HOST := $(or $(SEA_CROSS_HOST),desktop)
endif
BUILD   := build

BSK      := $(BAYSICK)/build/baysick
BSKRT    := $(BAYSICK)/build/libbaysickrt.a
PASSES   := seaparse seaname seacheck seaexpand seafuse sealoop sealower seaopt sealopt seavec seagen_a64 seagen_x64
LIBS_CANON := io diag tables lirrw limb f64emu fltlit layout ralloc
DATA_CANON := errors errno exits consts entries records mtab
RT_EXPECTED := rt_main rt_out rt_err rt_fmt rt_clock rt_math rt_mem rt_arr rt_str rt_args rt_sort rt_file

INCLUDES := include/limits.inc include/errors.inc include/rt.inc include/math_tables.inc
ASFLAGS_BASE := -arch arm64 -mmacosx-version-min=11.0 -I include -I tests
RT_ASFLAGS := -arch arm64 -mmacosx-version-min=11.0 -I include -I $(BAYSICK)/include
RT_SRCS := $(wildcard runtime/arm64_macos/*.s)
RT_OBJS := $(patsubst runtime/arm64_macos/%.s,$(BUILD)/obj/runtime/%.o,$(RT_SRCS))
BAYSICK_INC := $(wildcard $(BAYSICK)/include/runtime.inc $(BAYSICK)/include/limits.inc)

.PHONY: all runtime tools passes install check-baysick FORCE \
        test test-programs test-accept test-rt test-stage test-shape test-fusion test-protocol test-driver test-lib test-arith test-math test-la test-plots math-tables \
        check-data lines check-limits clean \
        check-includes check-contracts cross-includes cross cross-pack \
        w8-sim w8-log w8-log-update w8-sketch \
        bench bench-session bench-build bench-workloads bench-kernels bench-micro bench-numpy \
        bench-check bench-cross bench-report bench-charts bench-selftest
.DEFAULT_GOAL := all

all: install runtime tools passes

# ---- install directory ----------------------------------------------------------------
install: $(BUILD)/sea $(BUILD)/std.sea $(BUILD)/errors.inc $(BUILD)/limits.inc
	@if [ -f "$(BSKRT)" ]; then \
	  if ! cmp -s "$(BSKRT)" $(BUILD)/libbaysickrt.a; then cp "$(BSKRT)" $(BUILD)/libbaysickrt.a; fi; \
	else \
	  echo "make: $(BSKRT) not found: build Baysick first (make -C $(BAYSICK)); build/libbaysickrt.a not installed" >&2; \
	fi

$(BUILD)/sea: driver/sea
	@mkdir -p $(BUILD)
	cp driver/sea $@ && chmod +x $@
$(BUILD)/std.sea: std/std.sea
	@mkdir -p $(BUILD)
	cp std/std.sea $@
$(BUILD)/errors.inc: include/errors.inc
	@mkdir -p $(BUILD)
	cp include/errors.inc $@
$(BUILD)/limits.inc: include/limits.inc
	@mkdir -p $(BUILD)
	cp include/limits.inc $@

check-baysick:
	@if [ ! -x "$(BSK)" ] || [ ! -f "$(BSKRT)" ]; then \
	  echo "make: Baysick's compiler $(BSK) or runtime $(BSKRT) not found: run make in $(BAYSICK) first (BAYSICK=$(BAYSICK))" >&2; exit 1; \
	fi

# ---- runtime ----------------------------------------------------------------------------
runtime:
	@missing=""; for m in $(RT_EXPECTED); do \
	  [ -f runtime/arm64_macos/$$m.s ] || missing="$$missing $$m.s"; done; \
	if [ -n "$$missing" ]; then \
	  echo "make: runtime/arm64_macos: not written yet:$$missing" >&2; \
	fi
	@if [ -z "$(RT_SRCS)" ]; then \
	  echo "make: runtime/arm64_macos has no assembly sources: $(BUILD)/libsea.a not built" >&2; \
	else \
	  $(MAKE) --no-print-directory $(BUILD)/libsea.a; \
	fi

$(BUILD)/libsea.a: $(RT_OBJS)
	rm -f $@
	ar rcs $@ $(RT_OBJS)

$(BUILD)/obj/runtime/%.o: runtime/arm64_macos/%.s $(INCLUDES) $(BAYSICK_INC)
	@mkdir -p $(dir $@)
	$(AS) $(RT_ASFLAGS) -o $@ $<

# ---- tools ------------------------------------------------------------------------------
# gendata is standalone; seaval and lirchk are built like a pass (own file + modules + DATA + 99999 END,
# tools/seaval.build.list, same format as passes/<pass>/build.list).
tools:
	@if [ -f tools/gendata.bas ]; then $(MAKE) --no-print-directory $(BUILD)/tools/gendata || exit 1; \
	else echo "make: tools/gendata.bas not written yet" >&2; fi
	@if [ -f tools/seaval.bas ]; then $(MAKE) --no-print-directory $(BUILD)/tools/seaval || exit 1; \
	else echo "make: tools/seaval.bas not written yet" >&2; fi
	@if [ -f tools/lirchk.bas ]; then $(MAKE) --no-print-directory $(BUILD)/tools/lirchk || exit 1; \
	else echo "make: tools/lirchk.bas not written yet" >&2; fi

$(BUILD)/tools/gendata: tools/gendata.bas | check-baysick
	@mkdir -p $(BUILD)/tools
	$(BSK) $< -o $@

$(BUILD)/tools/seaval: $(BUILD)/gen/seaval.bas | check-baysick
	@mkdir -p $(BUILD)/tools
	$(BSK) $(BUILD)/gen/seaval.bas -o $@

$(BUILD)/gen/seaval.bas: FORCE | $(BUILD)/tools/gendata
	@sh -c "$$GEN_PASS" gen_pass seaval tools/seaval.bas tools/seaval.build.list

$(BUILD)/tools/lirchk: $(BUILD)/gen/lirchk.bas | check-baysick
	@mkdir -p $(BUILD)/tools
	$(BSK) $(BUILD)/gen/lirchk.bas -o $@

$(BUILD)/gen/lirchk.bas: FORCE | $(BUILD)/tools/gendata
	@sh -c "$$GEN_PASS" gen_pass lirchk tools/lirchk.bas tools/lirchk.build.list

# ---- passes -----------------------------------------------------------------------------
# build/gen/<pass>.bas is regenerated on every build (FORCE) and replaced only if its content
# changed, so build/<pass> is recompiled exactly when the generated program differs.
passes:
	@if [ -f tools/gendata.bas ]; then $(MAKE) --no-print-directory $(BUILD)/tools/gendata || exit 1; fi; \
	for p in $(PASSES); do \
	  if ls passes/$$p/*.bas > /dev/null 2>&1; then \
	    $(MAKE) --no-print-directory $(BUILD)/$$p || exit 1; \
	  else \
	    echo "make: pass $$p not written yet (no passes/$$p/*.bas)" >&2; \
	  fi; \
	done

define PASS_RULES
$$(BUILD)/$(1): $$(BUILD)/gen/$(1).bas | check-baysick
	$$(BSK) $$(BUILD)/gen/$(1).bas -o $$@

$$(BUILD)/gen/$(1).bas: FORCE
	@sh -c "$$$$GEN_PASS" gen_pass $(1) "passes/$(1)/*.bas" passes/$(1)/build.list
endef
$(foreach p,$(PASSES),$(eval $(call PASS_RULES,$(p))))

# The generator: $1 = program name, $2 = its own source files, $3 = its build list. Parts in the order of DESIGN.md 2.6.3.
define GEN_SCRIPT
p=$$1; own=$$2; list=$$3; out=$(BUILD)/gen/$$p.bas
[ -f $$list ] || { echo "make: $$list missing" >&2; exit 1; }
libs=$$(awk '$$1 == "lib" { for (i = 2; i <= NF; i++) print $$i }' $$list)
data=$$(awk '$$1 == "data" { for (i = 2; i <= NF; i++) print $$i }' $$list)
for w in $$libs; do case " $(LIBS_CANON) " in *" $$w "*) ;; *) echo "make: $$list: unknown module '$$w'" >&2; exit 1 ;; esac; done
for w in $$data; do case " $(DATA_CANON) " in *" $$w "*) ;; *) echo "make: $$list: unknown DATA block '$$w'" >&2; exit 1 ;; esac; done
case " $$(echo $$libs) " in *" lirrw "*) for w in $$libs; do case $$w in limb|f64emu) echo "make: $$list: lirrw cannot be loaded with $$w (their lines overlap, DESIGN.md 2.6.3)" >&2; exit 1 ;; esac; done ;; esac
mkdir -p $(BUILD)/gen; t=$$(mktemp -d "$${TMPDIR:-/tmp}/sea-gen.XXXXXX") || exit 1
trap 'rm -rf "$$t"' EXIT
: > $$t/prog.bas
for f in $$own; do awk 1 "$$f" >> $$t/prog.bas; done
for m in $(LIBS_CANON); do
  for w in $$libs; do
    if [ "$$w" = "$$m" ]; then
      [ -f passes/lib/$$m.bas ] || { echo "make: $$list: passes/lib/$$m.bas not written yet" >&2; exit 1; }
      awk 1 passes/lib/$$m.bas >> $$t/prog.bas
    fi
  done
done
blocks=
for b in $(DATA_CANON); do for w in $$data; do [ "$$w" = "$$b" ] && blocks="$$blocks $$b"; done; done
if [ -n "$$blocks" ]; then
  [ -x $(BUILD)/tools/gendata ] || { echo "make: $(BUILD)/tools/gendata not built (tools/gendata.bas not written yet?); needed for $$p" >&2; exit 1; }
  gd=$$(cd $(BUILD)/tools && pwd)/gendata
  printf '%s\n' $$blocks | (cd include && "$$gd") >> $$t/prog.bas || { echo "make: gendata failed for $$p" >&2; exit 1; }
fi
echo "99999 END" >> $$t/prog.bas
if cmp -s $$t/prog.bas $$out; then :; else cp $$t/prog.bas $$out; fi
endef
export GEN_PASS = $(GEN_SCRIPT)

FORCE:

# ---- tests ------------------------------------------------------------------------------
# run_group SCRIPT [ARGS]: a missing script is a failure with a clear message.
define RUN_SCRIPT
	@if [ ! -f $(1) ]; then echo "make: $(1) not written yet" >&2; exit 1; fi
	BUILD=$(BUILD) BAYSICK=$(BAYSICK) sh $(1)
endef

test-programs: all
	$(call RUN_SCRIPT,tests/run.sh)
test-rt: runtime
	$(call RUN_SCRIPT,tests/rt/run_rt.sh)
test-stage: all
	$(call RUN_SCRIPT,tests/stage.sh)
test-shape: all
	$(call RUN_SCRIPT,tests/shape.sh)
test-fusion: all
	$(call RUN_SCRIPT,tests/fusion.sh)
test-plots: all
	$(call RUN_SCRIPT,tests/plots.sh)
test-accept: all
	@for s in tests/accept4.sh tests/accept.sh; do \
	    if [ ! -f $$s ]; then echo "make: $$s not written yet" >&2; rc=1; continue; fi; \
	    BUILD=$(BUILD) BAYSICK=$(BAYSICK) sh $$s || rc=1; \
	done; exit $${rc:-0}
test-protocol: all
	$(call RUN_SCRIPT,tests/protocol.sh)
test-driver: install
	$(call RUN_SCRIPT,tests/driver_check.sh)
test-lib: tools
	$(call RUN_SCRIPT,tests/lib_check.sh)
test-arith: tools
	$(call RUN_SCRIPT,tests/arith_check.sh)
test-math: runtime
	@if [ ! -f tests/math/math_check.c ]; then echo "make: tests/math/math_check.c not written yet" >&2; exit 1; fi
	@mkdir -p $(BUILD)/obj
	env -u SDKROOT xcrun cc -O1 -ffp-contract=off -Wall -o $(BUILD)/obj/math_check tests/math/math_check.c $(BUILD)/libsea.a -lm
	$(BUILD)/obj/math_check tests/math

# The linear-algebra checks (DESIGN.md 2.13.8, L-ja, L-jd). The header is derived from the contract
# files only; la_check.c defines main and _sea_sites, so it links libsea.a without rt_main.o.
LA_DIR := $(BUILD)/obj/la
$(LA_DIR)/sea_consts.h: tests/la/gen_consts.sh include/rt.inc include/limits.inc include/errors.inc
	@mkdir -p $(LA_DIR)
	sh tests/la/gen_consts.sh $@
test-la: all $(LA_DIR)/sea_consts.h
	@for f in tests/la/la_check.c tests/la/la_link.sh; do \
	    [ -f $$f ] || { echo "make: $$f not written yet" >&2; exit 1; }; done
	@st=0; \
	echo "env -u SDKROOT xcrun cc -std=c11 -O2 -Wall -Wextra -ffp-contract=off -I $(LA_DIR) -o $(LA_DIR)/la_check tests/la/la_check.c $(BUILD)/libsea.a $(BUILD)/libbaysickrt.a"; \
	if env -u SDKROOT xcrun cc -std=c11 -O2 -Wall -Wextra -ffp-contract=off -I $(LA_DIR) -o $(LA_DIR)/la_check \
	        tests/la/la_check.c $(BUILD)/libsea.a $(BUILD)/libbaysickrt.a; then \
	    $(LA_DIR)/la_check || st=1; \
	else echo "FAIL la/la_check: build failed"; st=1; fi; \
	BUILD=$(BUILD) BAYSICK=$(BAYSICK) sh tests/la/la_link.sh || st=1; \
	exit $$st

# Developer check (not part of make test): the committed tables equal their definitions.
math-tables:
	timeout 120 uv run --with mpmath python tools/math_tables.py --check

check-data: tools
	$(call RUN_SCRIPT,tests/check_data.sh)

# Every group runs even if an earlier one fails; the exit status is 1 if any failed.
test: all check-contracts
	@st=0; \
	for g in test-driver check-data test-lib test-arith test-math test-la test-rt test-stage test-shape test-fusion test-protocol test-programs test-plots test-accept; do \
	  echo "== make $$g"; \
	  $(MAKE) --no-print-directory $$g || { echo "== $$g FAILED"; st=1; }; \
	done; \
	if [ $$st -eq 0 ]; then echo "== all test groups passed"; else echo "== some test groups failed"; fi; \
	exit $$st

lines:
	@BUILD=$(BUILD) BAYSICK=$(BAYSICK) sh tools/passlines.sh lines
check-limits:
	@BUILD=$(BUILD) BAYSICK=$(BAYSICK) sh tools/passlines.sh limits

clean:
	rm -rf $(BUILD)

# ---- contract checks (DESIGN.md 2.6, 6.2) -------------------------------------------------
# The include files are shared with the x86_64-linux runtime (GNU as), where
# `//` only starts a comment at the beginning of a line: a trailing comment
# must be written /* ... */ (Baysick DESIGN.md 3.4). The grep enforces it.
check-contracts: $(INCLUDES) include/passes.txt docs/DESIGN.md tests/check_contracts.sh
	@sh tests/check_contracts.sh

check-includes: check-contracts $(INCLUDES) tests/include_check.s tests/include_asserts.inc
	@if [ ! -f "$(BAYSICK)/include/limits.inc" ] || [ ! -f "$(BAYSICK)/include/runtime.inc" ]; then \
	  echo "make: Baysick's include/limits.inc and include/runtime.inc not found under BAYSICK=$(BAYSICK)" >&2; exit 1; \
	fi
	@if grep -nE '^[[:space:]]*[^[:space:]/].*//' $(INCLUDES) tests/include_asserts.inc; then \
	  echo "make: trailing // comment in a shared include file (use /* ... */)" >&2; exit 1; \
	fi
	@t=$$(mktemp -d "$${TMPDIR:-/tmp}/sea-incl.XXXXXX") || exit 1; \
	b=$$(cd "$(BAYSICK)" && pwd); \
	printf '// generated by make check-includes\n.include "%s/include/limits.inc"\n.include "%s/include/runtime.inc"\n' "$$b" "$$b" > "$$t/bsk_contract.inc"; \
	echo "$(AS) $(ASFLAGS_BASE) -I $$t -o $$t/include_check.o tests/include_check.s"; \
	$(AS) $(ASFLAGS_BASE) -I "$$t" -o "$$t/include_check.o" tests/include_check.s; st=$$?; \
	rm -rf "$$t"; \
	if [ $$st -ne 0 ]; then exit $$st; fi
	@t=$$(mktemp -d "$${TMPDIR:-/tmp}/sea-mtab.XXXXXX") || exit 1; \
	printf '.include "math_tables.inc"\n    .section __TEXT,__const\n    SEA_EMIT_MATH_TABLES\n' > "$$t/mt.s"; \
	echo "$(AS) $(ASFLAGS_BASE) -o $$t/mt.o $$t/mt.s (math_tables.inc)"; \
	$(AS) $(ASFLAGS_BASE) -o "$$t/mt.o" "$$t/mt.s"; st=$$?; \
	rm -rf "$$t"; \
	if [ $$st -ne 0 ]; then exit $$st; fi
	@echo "include files assemble, layout assertions hold, no clash with Baysick's include/limits.inc and include/runtime.inc"

cross-includes:
	sh tests/cross_includes.sh -H $(CROSS_HOST) -B "$(BAYSICK)"

# ---- x86_64-linux cross testing (DESIGN.md 6.6.1) -----------------------------------------
# cross-pack: the bundle build/x86_64-linux-bundle (removed first); cross: pack, ship by ssh to
# HOST (default desktop), run there, report. Both need seagen_x64 and the x86_64 runtime.
cross-pack: all
	rm -rf $(BUILD)/x86_64-linux-bundle
	SEA=$(BUILD)/sea BAYSICK=$(BAYSICK) sh tests/cross_pack.sh -o $(BUILD)/x86_64-linux-bundle

cross: all
	SEA=$(BUILD)/sea BAYSICK=$(BAYSICK) sh tests/cross.sh -H $(CROSS_HOST)

# ---- W8: the EV CAN workload's host simulator and committed log (DESIGN.md 2.16.5-2.16.7) ---
# Developer targets on the Mac only, never part of make test or make cross (L-nx). The
# simulator is C++20 built with xcrun c++; the sketch is compiled unmodified through
# host/sketch.cpp. Both builds use -Wfloat-conversion -Wdouble-promotion -Werror, and the
# second runs under the undefined-behaviour and address sanitizers (L-nf).
W8DIR   := workloads/w8_ev_can
W8HOST  := $(W8DIR)/host
W8BUILD := $(BUILD)/w8
W8CXX   := xcrun c++
W8WARN  := -Wall -Wextra -Wfloat-conversion -Wdouble-promotion -Werror -I $(W8HOST)/include
W8SRCS  := $(W8HOST)/main.cpp $(W8HOST)/mock_core.cpp $(W8HOST)/mock_twai.cpp \
           $(W8HOST)/model.cpp $(W8HOST)/sketch.cpp
W8DEPS  := $(W8SRCS) $(W8HOST)/sim.h $(W8HOST)/model.h $(W8HOST)/include/Arduino.h \
           $(W8HOST)/include/driver/twai.h $(W8DIR)/w8_ev_can/w8_ev_can.ino \
           $(W8DIR)/w8_ev_can/w8_can_msgs.h Makefile
W8SKETCH_RE := (w8_ev_can\.ino|w8_can_msgs\.h):[0-9]+:[0-9]+: warning

# The floating-literal check of DESIGN.md 2.16.7 (2): comments and string and character
# literals are stripped (state kept across lines for block comments), hexadecimal integer
# literals are replaced by 0, and no line may then match [0-9]\.[0-9]|[0-9][eE][+-]?[0-9].
# (\047 is the single quote.) A quote between two digits (a C++14 digit separator) is removed
# first, so 1'000.5 is caught. Prints each offending line and exits 1 if there is one.
define W8_FLOATLIT_AWK
FNR == 1 { st = 0 }
{
    if (st != 2) st = 0
    s = $$0; out = ""
    while (match(s, /[0-9]\047[0-9]/)) s = substr(s, 1, RSTART) substr(s, RSTART + 2)
    n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1); d = substr(s, i + 1, 1)
        if (st == 2) { if (c == "*" && d == "/") { st = 0; out = out " "; i += 2 } else i++; continue }
        if (st == 3 || st == 4) {
            if (c == "\\") { i += 2; continue }
            if ((st == 3 && c == "\"") || (st == 4 && c == "\047")) st = 0
            i++; continue
        }
        if (c == "/" && d == "/") break
        if (c == "/" && d == "*") { st = 2; i += 2; continue }
        if (c == "\"") { st = 3; out = out " "; i++; continue }
        if (c == "\047") { st = 4; out = out " "; i++; continue }
        out = out c; i++
    }
    gsub(/0[xX][0-9a-fA-F]+/, "0", out)
    if (out ~ /[0-9]\.[0-9]|[0-9][eE][+-]?[0-9]/) { print FILENAME ":" FNR ": " $$0; bad = 1 }
}
END { exit bad }
endef
export W8_FLOATLIT_AWK

# The floating-point checks (1) and (2) over the sketch, its header and every host file;
# check (3) is the -Werror flags of both builds.
define w8-float-checks
@files="$(W8DIR)/w8_ev_can/w8_ev_can.ino $(W8DIR)/w8_ev_can/w8_can_msgs.h $$(find $(W8HOST) -type f | LC_ALL=C sort)"; \
if grep -n -w -e float -e double $$files; then \
  echo "w8: float or double found (DESIGN.md 2.16.7)" >&2; exit 1; \
fi; \
if ! LC_ALL=C awk "$$W8_FLOATLIT_AWK" $$files; then \
  echo "w8: decimal floating literal found (DESIGN.md 2.16.7)" >&2; exit 1; \
fi; \
echo "w8: floating-point checks pass (no float, double or floating literal)"
endef

w8-sim: $(W8BUILD)/w8sim

$(W8BUILD)/w8sim: $(W8DEPS)
	@mkdir -p $(W8BUILD)
	$(W8CXX) -std=c++20 -O2 $(W8WARN) -o $@ $(W8SRCS)

$(W8BUILD)/w8sim_san: $(W8DEPS)
	@mkdir -p $(W8BUILD)
	$(W8CXX) -std=c++20 -O0 -g -fsanitize=undefined,address -fno-sanitize-recover=all $(W8WARN) -o $@ $(W8SRCS)

# Run both builds, the car run (120 s, with its bus log) and the bench run (5 s, Serial only),
# into the temporary directory $$t: $$t/<build>.log, .serial and .bench.
define w8-run-both
for b in w8sim w8sim_san; do \
  : > "$$t/$$b.err"; \
  $(W8BUILD)/$$b --seconds 120 --log "$$t/$$b.log" --serial "$$t/$$b.serial" 2>>"$$t/$$b.err" && \
  $(W8BUILD)/$$b --bench --seconds 5 --serial "$$t/$$b.bench" 2>>"$$t/$$b.err" || { cat "$$t/$$b.err" >&2; echo "w8: $$b failed" >&2; st=1; break; }; \
  if [ -s "$$t/$$b.err" ]; then cat "$$t/$$b.err" >&2; echo "w8: $$b wrote to stderr (frames lost or a warning)" >&2; st=1; break; fi; \
done
endef

w8-log: $(W8BUILD)/w8sim $(W8BUILD)/w8sim_san
	$(w8-float-checks)
	@t=$$(mktemp -d "$${TMPDIR:-/tmp}/sea-w8.XXXXXX") || exit 1; st=0; \
	$(w8-run-both); \
	if [ $$st -eq 0 ]; then \
	  for b in w8sim w8sim_san; do \
	    for pair in "log:w8_ev_can.log" "serial:serial.txt" "bench:bench_serial.txt"; do \
	      if ! cmp -s "$$t/$$b.$${pair%%:*}" "$(W8DIR)/$${pair#*:}"; then \
	        echo "w8-log: $(W8DIR)/$${pair#*:} differs (build $$b)"; st=1; break 2; \
	      fi; \
	    done; \
	  done; \
	fi; \
	rm -rf "$$t"; \
	if [ $$st -ne 0 ]; then exit 1; fi; \
	echo "w8-log: identical ($$(wc -l < $(W8DIR)/w8_ev_can.log | tr -d ' ') lines, $$(wc -c < $(W8DIR)/w8_ev_can.log | tr -d ' ') bytes)"

w8-log-update: $(W8BUILD)/w8sim $(W8BUILD)/w8sim_san
	$(w8-float-checks)
	@t=$$(mktemp -d "$${TMPDIR:-/tmp}/sea-w8.XXXXXX") || exit 1; st=0; \
	$(w8-run-both); \
	if [ $$st -eq 0 ]; then \
	  for x in log serial bench; do \
	    if ! cmp -s "$$t/w8sim.$$x" "$$t/w8sim_san.$$x"; then \
	      echo "w8-log-update: the two builds disagree ($$x)" >&2; st=1; break; \
	    fi; \
	  done; \
	fi; \
	if [ $$st -eq 0 ]; then \
	  d="$(W8DIR)"; \
	  if /bin/cp -f "$$t/w8sim.log" "$$d/.w8tmp.log" && \
	     /bin/cp -f "$$t/w8sim.serial" "$$d/.w8tmp.serial" && \
	     /bin/cp -f "$$t/w8sim.bench" "$$d/.w8tmp.bench"; then \
	    /bin/mv -f "$$d/.w8tmp.log" "$$d/w8_ev_can.log" && \
	    /bin/mv -f "$$d/.w8tmp.serial" "$$d/serial.txt" && \
	    /bin/mv -f "$$d/.w8tmp.bench" "$$d/bench_serial.txt" || st=1; \
	  else st=1; fi; \
	  /bin/rm -f "$$d/.w8tmp.log" "$$d/.w8tmp.serial" "$$d/.w8tmp.bench"; \
	fi; \
	rm -rf "$$t"; \
	if [ $$st -ne 0 ]; then exit 1; fi; \
	echo "w8-log-update: wrote $(W8DIR)/w8_ev_can.log ($$(wc -l < $(W8DIR)/w8_ev_can.log | tr -d ' ') lines, $$(wc -c < $(W8DIR)/w8_ev_can.log | tr -d ' ') bytes), serial.txt, bench_serial.txt"

# Compile only (no upload): exit 0 and no warning located in the sketch or its header (a
# warning inside the core's own files does not fail it).
w8-sketch:
	@out=$$(arduino-cli compile --fqbn esp32:esp32:esp32:UploadSpeed=115200 --warnings all $(W8DIR)/w8_ev_can 2>&1); st=$$?; \
	printf '%s\n' "$$out"; \
	if [ $$st -ne 0 ]; then echo "w8-sketch: arduino-cli failed (exit $$st)" >&2; exit 1; fi; \
	if printf '%s\n' "$$out" | grep -E '$(W8SKETCH_RE)'; then \
	  echo "w8-sketch: warnings in the sketch" >&2; exit 1; \
	fi; \
	echo "w8-sketch: compiles, no warning in the sketch or w8_can_msgs.h"

# ---- benchmarks (DESIGN.md 2.17.9) ----------------------------------------------------------------
# Mac only; each target depends on all; none is part of make test, make cross or any other target.
# BENCH_OUT (relative to this repository, the working directory of make) is passed as --out,
# BENCH_QUICK=1 as --quick, BENCH_CROSS_ARGS (-H HOST) to the --cross runs. make bench runs the
# steps in the order of L-pl and stops at the first failing one; with BENCH_QUICK=1 it ends after
# bench-numpy (check.py refuses quick records), else it ends with bench-check.
BENCH_OUT        ?= bench/results/p10
BENCH_QUICK      ?=
BENCH_CROSS_ARGS ?=
BENCH_Q := $(if $(filter 1,$(BENCH_QUICK)),--quick,)

define bench-session-cmd
sh bench/session.sh "$(BENCH_OUT)" $(BENCH_Q)
endef
define bench-build-cmd
sh bench/workloads.sh build --out "$(BENCH_OUT)" $(BENCH_Q)
sh bench/kernels.sh build --out "$(BENCH_OUT)" $(BENCH_Q)
sh bench/micro.sh --current build --out "$(BENCH_OUT)" $(BENCH_Q)
endef
define bench-workloads-cmd
sh bench/workloads.sh measure --out "$(BENCH_OUT)" $(BENCH_Q)
endef
define bench-kernels-cmd
sh bench/kernels.sh measure --out "$(BENCH_OUT)" $(BENCH_Q)
endef
define bench-micro-cmd
sh bench/micro.sh --current measure --out "$(BENCH_OUT)" $(BENCH_Q)
endef
define bench-numpy-cmd
sh bench/numpy.sh measure --out "$(BENCH_OUT)" $(BENCH_Q)
endef
# The checker's status is kept without a pipe (POSIX sh has no pipefail): check.txt exists only
# for a verdict (0 or 1); a setup error (2) leaves none.
define bench-check-cmd
@[ -d "$(BENCH_OUT)" ] || { echo "bench-check: '$(BENCH_OUT)' is not a directory" >&2; exit 2; }; \
st=0; uv run --no-project python -I bench/check.py "$(BENCH_OUT)" >"$(BENCH_OUT)/check.txt" || st=$$?; \
if [ $$st -eq 2 ]; then rm -f "$(BENCH_OUT)/check.txt"; else cat "$(BENCH_OUT)/check.txt"; fi; exit $$st
endef

bench-session: all
	$(bench-session-cmd)

bench-build: all
	$(bench-build-cmd)

bench-workloads: all
	$(bench-workloads-cmd)

bench-kernels: all
	$(bench-kernels-cmd)

bench-micro: all
	$(bench-micro-cmd)

bench-numpy: all
	$(bench-numpy-cmd)

bench-check: all
	$(bench-check-cmd)

bench: all
	$(bench-session-cmd)
	$(bench-build-cmd)
	$(bench-workloads-cmd)
	$(bench-kernels-cmd)
	$(bench-micro-cmd)
	$(bench-numpy-cmd)
ifeq ($(BENCH_Q),)
	$(bench-check-cmd)
else
	@echo "bench: quick mode: every step done; no pass check (check.py refuses quick records)"
endif

bench-cross: all
	sh bench/workloads.sh --cross --out "$(BENCH_OUT)" $(BENCH_Q) $(BENCH_CROSS_ARGS)
	sh bench/kernels.sh --cross --out "$(BENCH_OUT)" $(BENCH_Q) $(BENCH_CROSS_ARGS)
	sh bench/micro.sh --current --cross --out "$(BENCH_OUT)" $(BENCH_Q) $(BENCH_CROSS_ARGS)

bench-report: all
	uv run --no-project python -I bench/report.py "$(BENCH_OUT)"

bench-charts: all
	uv run --no-project python -I bench/charts.py $(BENCH_OUT) docs/img

bench-selftest: all
	sh bench/spawn_test.sh
	uv run --no-project python -I bench/check.py --self-test
