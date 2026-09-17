# cordic-engine master Makefile
#
#   make matlab              oracle check, quantization sweep, pick operating point, export vectors
#   make sim                 directed + sweep testbenches (every exported config), bit-exact diff
#   make sim-directed        tb/tb_cordic_directed.sv only        (N=, W= override the config)
#   make sim-sweep           tb/tb_cordic_sweep.sv at one config  (N=, W=)
#   make sim-... WAVES=1     also dump build/tb_*.vcd
#   make synth               Vivado out-of-context synthesis + P&R at the chosen N_ITER
#   make sweep               same across N_ITER = 8,12,16,20 -> docs/ppa_table.md
#   make vm-synth / vm-sweep the same two, run inside the Parallels Windows VM (Apple Silicon)

IVERILOG ?= iverilog
VVP      ?= vvp
VIVADO   ?= vivado
PYTHON   ?= python3
MATLAB   ?= $(shell command -v matlab 2>/dev/null || echo /Applications/MATLAB_R2026a.app/bin/matlab)

RTL_DIR   = rtl
TB_DIR    = tb
VEC_DIR   = tb/vectors
BUILD_DIR = build

# operating point chosen by matlab/sweep_quantization.m (OP_N, OP_W)
include $(VEC_DIR)/operating_point.mk
N ?= $(OP_N)
W ?= $(OP_W)
SWEEP_N ?= 8 12 16 20

RTL_SRCS  = $(wildcard $(RTL_DIR)/*.sv)
RTL_DEPS  = $(RTL_SRCS) $(wildcard $(RTL_DIR)/*.svh)
# every exported golden file is a config to verify: cordic_N<N>_W<W>.csv -> <N>_<W>
CONFIGS   = $(patsubst $(VEC_DIR)/cordic_N%.csv,%,$(subst _W,_,$(wildcard $(VEC_DIR)/cordic_N*_W*.csv)))

IVFLAGS   = -g2012 -Wall -Wno-timescale -I $(RTL_DIR)
PLUSARGS  = $(if $(WAVES),+WAVES,)

.PHONY: all matlab sim sim-directed sim-sweep golden-diff synth sweep vm-synth vm-sweep clean
.SECONDARY:

all: sim

# ── MATLAB: models, quantization sweep, golden vectors ──────────────────────

matlab:
	cd matlab && $(MATLAB) -batch "run_all"

# ── Simulation (Icarus) ──────────────────────────────────────────────────────

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# build/tb_<name>_<N>_<W>.vvp
$(BUILD_DIR)/tb_cordic_directed_%.vvp: $(TB_DIR)/tb_cordic_directed.sv $(RTL_DEPS) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s tb_cordic_directed \
	  -Ptb_cordic_directed.N_ITER=$(word 1,$(subst _, ,$*)) -Ptb_cordic_directed.W=$(word 2,$(subst _, ,$*)) \
	  -o $@ $(RTL_SRCS) $<

$(BUILD_DIR)/tb_cordic_sweep_%.vvp: $(TB_DIR)/tb_cordic_sweep.sv $(RTL_DEPS) | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s tb_cordic_sweep \
	  -Ptb_cordic_sweep.N_ITER=$(word 1,$(subst _, ,$*)) -Ptb_cordic_sweep.W=$(word 2,$(subst _, ,$*)) \
	  -o $@ $(RTL_SRCS) $<

RUN_TARGETS = $(sort $(addprefix run-directed_,$(CONFIGS) $(N)_$(W)) $(addprefix run-sweep_,$(CONFIGS) $(N)_$(W)))
.PHONY: $(RUN_TARGETS)

$(RUN_TARGETS): run-%: $(BUILD_DIR)/tb_cordic_%.vvp
	@$(VVP) -N $< $(PLUSARGS) | grep -v '^ok ' | tee $(BUILD_DIR)/tb_cordic_$*.log
	@grep -q "TEST PASSED" $(BUILD_DIR)/tb_cordic_$*.log

sim-directed: run-directed_$(N)_$(W)
sim-sweep:    run-sweep_$(N)_$(W)

sim: $(addprefix run-directed_,$(CONFIGS)) $(addprefix run-sweep_,$(CONFIGS))
	@$(PYTHON) matlab/diff_cordic.py
	@echo "=== all testbenches passed, configs (N_W): $(CONFIGS) ==="

golden-diff:
	@$(PYTHON) matlab/diff_cordic.py

# ── Synthesis (Vivado, out-of-context) ──────────────────────────────────────

synth:
	$(VIVADO) -mode batch -nolog -nojournal -source tcl/cordic_synth.tcl -tclargs $(W) $(N)

sweep:
	$(VIVADO) -mode batch -nolog -nojournal -source tcl/cordic_synth.tcl -tclargs $(W) $(SWEEP_N)
	$(PYTHON) scripts/ppa_table.py

vm-synth:
	./scripts/vivado_in_parallels.sh $(W) $(N)

vm-sweep:
	./scripts/vivado_in_parallels.sh $(W) $(SWEEP_N)
	$(PYTHON) scripts/ppa_table.py

# ── Clean ───────────────────────────────────────────────────────────────────

clean:
	rm -rf $(BUILD_DIR) vivado .Xil *.jou *.log
