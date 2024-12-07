OBJ_DIR = obj
VERILATED_DIR = verilated

VERILATOR = verilator
VERILATOR_ARGS = --cc --make gmake -j 8 --trace --Mdir $(VERILATED_DIR) -Ihdl --MMD --MP $(VERILATOR_DEFINES)
PYTHON = python3

VERILATOR_INC = $(shell pkg-config --variable=includedir verilator)
VERILATOR_CPP = verilated.cpp verilated_vcd_c.cpp verilated_threads.cpp
VERILATOR_OBJS = $(patsubst %.cpp, $(OBJ_DIR)/verilator/%.o, $(VERILATOR_CPP))

IMGUI_CPP = imgui/imgui.cpp \
			imgui/imgui_draw.cpp \
			imgui/imgui_tables.cpp \
			imgui/imgui_widgets.cpp \
			imgui/backends/imgui_impl_sdl2.cpp \
			imgui/backends/imgui_impl_sdlrenderer2.cpp

IMGUI_OBJS = $(patsubst %.cpp, $(OBJ_DIR)/%.o, $(IMGUI_CPP))

CC=cc
CXX=c++
CPPFLAGS= --std=gnu++17 -g
CPPFLAGS+=-I$(VERILATED_DIR) $(shell pkg-config --cflags verilator)
CPPFLAGS+=$(shell pkg-config --cflags sdl2)
CPPFLAGS+=-Iimgui/ -Iimgui/backends/

LDFLAGS=-g -Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv

LDLIBS=$(shell pkg-config --libs sdl2)

VERILATOR_DEFINES = #-DONE_CYCLE_DECODE_DELAY # -DFULL_OPERAND_FETCH

HDL_SRC = hdl/types.sv \
		  hdl/bus_control_unit_v35.sv \
		  hdl/nec_divider.sv \
		  hdl/v33.sv \
		  hdl/nec_decode.sv \
		  hdl/alu.sv \
		  hdl/pic.sv

HDL_GEN = hdl/opcodes.svh hdl/enums.svh

$(VERILATED_DIR)/v33.mk: $(HDL_SRC) $(HDL_GEN)
	$(VERILATOR) $(VERILATOR_ARGS) -o v33 --prefix v33 --top V33 $(HDL_SRC)

$(VERILATED_DIR)/v33__ALL.a: $(VERILATED_DIR)/v33.mk $(HDL_SRC) $(HDL_GEN)
	$(MAKE) -C $(VERILATED_DIR) -f v33.mk

$(OBJ_DIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) -o $@ -c $< $(CPPFLAGS)

$(OBJ_DIR)/verilator/%.o: $(VERILATOR_INC)/%.cpp
	@mkdir -p $(dir $@)
	$(CXX) -o $@ -c $< $(CPPFLAGS)

$(OBJ_DIR)/bench/irem.o: $(VERILATED_DIR)/v33__ALL.a

irem: $(OBJ_DIR)/bench/irem.o $(IMGUI_OBJS) $(VERILATOR_OBJS) $(VERILATED_DIR)/v33__ALL.a 
	$(CXX) -o $@ $^ $(CPPFLAGS) $(LDFLAGS) $(LDLIBS) -lpthread
	

hdl/opcodes%svh hdl/opcode_enums%yaml: hdl/opcodes.yaml hdl/gen_decode.py
	$(PYTHON) hdl/gen_decode.py

hdl/enums.svh: hdl/enums.yaml hdl/opcode_enums.yaml hdl/gen_enums.py
	$(PYTHON) hdl/gen_enums.py

.PHONY: clean

clean:
	rm -r $(OBJ_DIR) $(VERILATED_DIR)

