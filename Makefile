BUILD_DIR = build
VERILATOR = verilator
VERILATOR_ARGS = --exe --cc --build -j 8 --trace --Mdir $(BUILD_DIR) -Ihdl --MMD --MP $(VERILATOR_DEFINES)
PYTHON = python3

VERILATOR_DEFINES = #-DONE_CYCLE_DECODE_DELAY # -DFULL_OPERAND_FETCH

HDL_SRC = hdl/types.sv \
		  hdl/bus_control_unit_v35.sv \
		  hdl/nec_divider.sv \
		  hdl/v33.sv \
		  hdl/nec_decode.sv \
		  hdl/alu.sv \
		  hdl/pic.sv

HDL_GEN = hdl/opcodes.svh hdl/enums.svh

TIMING_TESTS = \
				nop_loop \
				mov_2byte_from_mem \
				mov_2byte_to_mem \
				lock_mov_2byte_from_mem \
				lock_mov_2byte_to_mem \
				mov_3byte_from_mem \
				mov_3byte_to_mem \
				add_2byte_from_mem \
				add_2byte_to_mem \
				lock_add_2byte_from_mem \
				lock_add_2byte_to_mem \
				add_3byte_from_mem \
				add_3byte_to_mem \
				branch_always \
				two_cycle_1 \
				two_cycle_2 \
				two_cycle_3 \
				two_cycle_4 \
				rol_1 \
				rol_2 \
				rol_3 \
				rol_4 \
				rol_5 \
				lock_nop_loop \
				two_cycle_1_w_lock \
				push_ax \
				stosw_reverse \
				alu_timing \
				block_timing \
				mov_timing \
				stack_timing \
				misc_timing \
				shift_timing \
				mul_timing \
				div_timing \
				nec_timing \
				branch_timing

TIMING_TEST_TRACES = $(patsubst %,traces/sim/%.txt,$(TIMING_TESTS))

TIMING_TEST_TRACES_M107 = $(patsubst %,traces/m107/%.txt,$(TIMING_TESTS))

all: $(TIMING_TEST_TRACES)

m107: $(TIMING_TEST_TRACES_M107)

$(BUILD_DIR)/v33: $(HDL_SRC) $(HDL_GEN) bench/main.cpp Makefile
	$(VERILATOR) $(VERILATOR_ARGS) -o v33 --prefix v33 --top V33 $(HDL_SRC) bench/main.cpp

$(BUILD_DIR)/test_186: $(HDL_SRC) $(HDL_GEN) bench/test_186.cpp Makefile
	$(VERILATOR) $(VERILATOR_ARGS) -o test_186 --prefix v33 --top V33 $(HDL_SRC) bench/test_186.cpp

$(BUILD_DIR)/bcu: $(HDL_SRC) $(HDL_GEN) bench/bcu.cpp Makefile
	$(VERILATOR) $(VERILATOR_ARGS) -o bcu --prefix bus_control_unit --top bus_control_unit_v35 $(HDL_SRC) bench/bcu.cpp

$(BUILD_DIR)/irem: $(HDL_SRC) $(HDL_GEN) bench/irem.cpp Makefile
	$(VERILATOR) $(VERILATOR_ARGS) -o irem --prefix v33 --top V33 $(HDL_SRC) bench/irem.cpp

hdl/opcodes%svh hdl/opcode_enums%yaml: hdl/opcodes.yaml hdl/gen_decode.py
	$(PYTHON) hdl/gen_decode.py

hdl/enums.svh: hdl/enums.yaml hdl/opcode_enums.yaml hdl/gen_enums.py
	$(PYTHON) hdl/gen_enums.py

testrom/build/test_%/cpu.bin: ALWAYS
	$(MAKE) -C testrom TEST=$*

.PRECIOUS: traces/sim/%.vcd
traces/sim/%.vcd: testrom/build/test_%/cpu.bin $(BUILD_DIR)/v33
	$(BUILD_DIR)/v33 $< $@

traces/sim/%.txt: traces/sim/%.vcd bench/extract_sim.py
	$(PYTHON) bench/extract_sim.py $< $@

traces/m107/%.txt: traces/m107/%.vcd bench/extract_hw.py
	$(PYTHON) bench/extract_hw.py $< $@

80186: $(BUILD_DIR)/test_186
	cd tests/80186 && ./run_tests.sh

cycles/%: traces/m107/%.txt traces/sim/%.txt traces/cycle_names.txt bench/compare_cycles.py
	bench/compare_cycles.py $* traces/m107/ traces/sim/ traces/cycle_names.txt
	

.PHONY: ALWAYS cycles 80186 m107

