@echo off
REM ============================================================================
REM FX-RV32-X FPGA 批量综合 — 一键启动
REM
REM 用法:
REM   run_synth_banks.bat         仅综合 (快速, ~20分钟)
REM   run_synth_banks.bat impl    综合+实现 (完整, ~2小时)
REM
REM 前提: Vivado 在 PATH 中, 或修改 VIVADO_BIN 变量
REM ============================================================================

setlocal

set VIVADO_BIN=C:\Xilinx\Vivado\2024.1\bin\vivado.bat
if not exist "%VIVADO_BIN%" set VIVADO_BIN=vivado

set SCRIPT_DIR=%~dp0

if "%1"=="impl" (
    echo === 模式: 综合 + 实现 (完整) ===
    call "%VIVADO_BIN%" -mode batch -source "%SCRIPT_DIR%synth_fpga_banks.tcl" -tclargs -impl 1
) else if "%1"=="gui" (
    echo === 打开 GUI 工程 ===
    call "%VIVADO_BIN%" -source "%SCRIPT_DIR%create_project.tcl"
) else (
    echo === 模式: 仅综合 (快速) ===
    echo === 如需完整实现, 运行: run_synth_banks.bat impl ===
    call "%VIVADO_BIN%" -mode batch -source "%SCRIPT_DIR%synth_fpga_banks.tcl" -tclargs -impl 0
)

echo.
echo === 结果保存在 vivado\synth_results\ ===
dir /b "%SCRIPT_DIR%synth_results\"

endlocal
