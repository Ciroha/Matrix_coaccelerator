# ==============================================================================
# Universal Makefile for Verilog Simulation and C Compilation
# Adaptable for Synopsys VCS and Icarus Verilog
#
# 使用方法:
#  make              - 编译 C 代码, 并用 iverilog 运行 Verilog 仿真
#  make SIM=vcs      - 编译 C 和 Verilog, 并用 VCS 运行仿真
#
#  make compile [SIM=vcs] - 仅编译 Verilog (VCS模式下会连带C代码)
#  make c_compile         - 仅编译 C 代码
#  make run [SIM=vcs]     - 运行 Verilog 仿真
#  make view [SIM=vcs]    - 打开波形查看器
#  make clean             - 清理所有生成的文件
# ==============================================================================

# --- 用户可配置变量 ---

# 1. 设置默认仿真器 (可以是 iverilog 或 vcs)
SIM ?= iverilog

# 2. Verilog 源文件列表 (vsrc/ 目录下)
SRC_FILES = vsrc/test_tpu.v \
            vsrc/tpu_top.v \
            vsrc/addr_sel.v \
            vsrc/sram_16x128b.v \
            vsrc/sram_32x8b.v \
            vsrc/systolic_controll.v \
            vsrc/systolic.v \
            vsrc/write_out.v \
            vsrc/sram_64x64b.v

# 3. C 语言源文件和可执行文件名
C_SRC  = csrc/runq.c \
		 csrc/tpu_interface.c
C_EXEC = runq_hw

# 4. 仿真顶层模块名
TOP_MODULE = test_tpu

# 5. 模型名称 (C 代码中使用)
MODEL_FILES = data/stories260K_q80.bin
TOKENIZER_FILES = data/tok512.bin
STEP = 20
TOKEN = "Once upon a time"

# --- 条件化工具和标志定义 (无需修改) ---

ifeq ($(SIM),vcs)
    # --- VCS 设置 ---
    TOOL_NAME      = Synopsys VCS
    COMPILER       = vcs
    COMPILER_FLAGS = -sverilog -full64 -kdb -lca -debug_access+all \
                     -D VCS_SIM \
                     -LDFLAGS "-Wl,--no-as-needed"
    #  -cc gcc-4.8 -cpp g++-4.8 (如果你的环境需要，可以取消这些注释)
    
    SIM_CMD        = ./simv
    SIM_FLAGS      = 
    
    WAVE_VIEWER    = verdi
    VIEWER_FLAGS   = -kdb -lca -ssf waveform.fsdb

    SIM_OUT        = simv
    WAVEFORM_FILE  = waveform.fsdb
    # 清理列表中包含 C 可执行文件
    CLEAN_FILES    = simv simv.daidir csrc *.log waveform.fsdb* verdiLog* novas.* ucli.key $(C_EXEC) *.txt

else
    # --- Icarus Verilog 设置 (默认) ---
    TOOL_NAME      = Icarus Verilog
    COMPILER       = iverilog
    COMPILER_FLAGS = -g2012 -Wall -D IVERILOG_SIM -s $(TOP_MODULE)
    
    SIM_CMD        = vvp
    SIM_FLAGS      = 
    
    WAVE_VIEWER    = gtkwave
    VIEWER_FLAGS   = waveform.vcd

    SIM_OUT        = tpu_sim # iverilog 编译输出文件名
    WAVEFORM_FILE  = waveform.vcd
    # 清理列表中包含 C 可执行文件
    CLEAN_FILES    = $(SIM_OUT) *.log *.vcd $(C_EXEC) *.txt

endif

# C 编译器和编译选项
CC = gcc
CFLAGS = -O2 -Wall -lm # -lm 用于链接数学库 (例如 math.h 中的函数)

# --- Makefile 规则 (通用) ---

.PHONY: all compile run view clean help c_compile

# 默认目标: 编译 C 代码，并编译/运行 Verilog 仿真
all: run

# Verilog 编译规则
compile: $(SRC_FILES)
	@echo "======================================================="
	@echo "INFO: Compiling Verilog for $(TOOL_NAME)..."
	@echo "======================================================="
ifeq ($(SIM),vcs)
# 对于VCS，将C源文件和Verilog源文件一起编译，并使用 -l 选项
	$(COMPILER) $(COMPILER_FLAGS) -o $(SIM_OUT) $(SRC_FILES) $(C_SRC) -l compile.log
else
# 对于Icarus Verilog，只编译Verilog文件，并使用重定向 > ... 2>&1
	$(COMPILER) $(COMPILER_FLAGS) -o $(SIM_OUT) $(SRC_FILES) > log/compile.log 2>&1
endif

# C 语言编译规则
c_compile: $(C_SRC)
	@echo "======================================================="
	@echo "INFO: Compiling C source file with $(CC)..."
	@echo "======================================================="
	$(CC) -o $(C_EXEC) $(C_SRC) $(CFLAGS)

# 仿真运行规则
run: c_compile compile
	@echo "======================================================="
	@echo "INFO: Running simulation with $(TOOL_NAME)..."
	@echo "======================================================="
	$(C_EXEC) $(MODEL_FILES) -z $(TOKENIZER_FILES) -n $(STEP) -i $(TOKEN)

# 波形查看规则
view:
	@echo "======================================================="
	@echo "INFO: Launching $(WAVE_VIEWER) to view waveform..."
	@echo "======================================================="
	@test -f $(WAVEFORM_FILE) && $(WAVE_VIEWER) $(VIEWER_FLAGS) & || echo "ERROR: Waveform file $(WAVEFORM_FILE) not found."

# 清理规则
clean:
	@echo "======================================================="
	@echo "INFO: Cleaning up generated files..."
	@echo "======================================================="
	@rm -rf $(CLEAN_FILES)
	@echo "Cleanup complete."

# 帮助信息
help:
	@echo "Universal Makefile for Verilog Simulation and C Compilation"
	@echo ""
	@echo "Usage:"
	@echo "  make                   - Compile C and run Verilog simulation with Icarus (default)"
	@echo "  make SIM=vcs           - Compile C/Verilog together and run with VCS"
	@echo ""
	@echo "Specific targets:"
	@echo "  make compile [SIM=vcs] - Only compile Verilog (VCS mode includes C)"
	@echo "  make c_compile         - Only compile the C source file"
	@echo "  make run [SIM=vcs]     - Run the Verilog simulation"
	@echo "  make view [SIM=vcs]    - Launch waveform viewer"
	@echo "  make clean             - Remove all generated files"
	@echo ""
