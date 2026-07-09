# 顶层模块名
TOP = core_top_sim

# 自动查找 rtl 目录下所有 .v 文件（排除 testbench）
SOURCES = $(shell find rtl -name "*.v" ! -name "tb_*.v")

# 仿真顶层 C++ 文件
SIM_CPP = sim_main.cpp

# Verilator 参数：--cc --exe --build 并行编译，并关闭致命警告
VERILATOR_FLAGS = --cc --exe --build -j 8 --top-module $(TOP) \
                  -Wno-fatal \
                  -Wno-PINMISSING \
                  -Wno-MULTIDRIVEN \
                  -Wno-LATCH \
                  -Wno-WIDTHTRUNC \
                  -Wno-WIDTHEXPAND \
                  -Wno-CASEINCOMPLETE \
                  -Wno-UNSIGNED

# 目标可执行文件
EXE = obj_dir/V$(TOP)

all: $(EXE)

$(EXE): $(SOURCES) $(SIM_CPP)
	verilator $(VERILATOR_FLAGS) $(SIM_CPP) $(SOURCES)

run: $(EXE)
	./$(EXE)

clean:
	rm -rf obj_dir

.PHONY: all run clean