@echo off
REM run_uvm.bat — Windows 一键启动 UVM 仿真
REM
REM 用法:
REM   run_uvm.bat                    默认: cpu_test_alu + alu_test.hex, 控制台
REM   run_uvm.bat gui                默认测试, GUI 波形模式
REM   run_uvm.bat intr               中断测试 (cpu_test_interrupt)
REM   run_uvm.bat hazard             冒险测试 (cpu_test_hazard)
REM   run_uvm.bat nested            嵌套中断 (cpu_test_nested)
REM   run_uvm.bat triple            三级嵌套 (cpu_test_triple)
REM   run_uvm.bat overflow           Bank溢出 (cpu_test_overflow)
REM   run_uvm.bat degradation        降级复用 (cpu_test_degradation)
REM   run_uvm.bat tailchain          尾链优化 (cpu_test_tailchain)
REM   run_uvm.bat context           寄存器完整性 (cpu_test_context)
REM   run_uvm.bat alu mytest.hex     指定 hex 文件的基础指令测试
REM   最后加 gui 参数开启波形 (如: run_uvm.bat nested gui)

set TEST_NAME=cpu_test_alu
set HEX_FILE=alu_test.hex
set GUI_MODE=0
set SHADOW_BANKS=4
set OVERFLOW_POLICY=0

REM 解析第一个参数
if not "%1"=="" (
    if "%1"=="gui" (
        set GUI_MODE=1
    ) else if "%1"=="intr" (
        set TEST_NAME=cpu_test_interrupt
        set HEX_FILE=intr_test.hex
    ) else if "%1"=="hazard" (
        set TEST_NAME=cpu_test_hazard
        set HEX_FILE=load_use_test.hex
    ) else if "%1"=="alu" (
        set TEST_NAME=cpu_test_alu
        if not "%2"=="" set HEX_FILE=%2
    ) else if "%1"=="nested" (
        set TEST_NAME=cpu_test_nested
        set HEX_FILE=nested_test.hex
    ) else if "%1"=="triple" (
        set TEST_NAME=cpu_test_triple
        set HEX_FILE=triple_nested_test.hex
    ) else if "%1"=="overflow" (
        set TEST_NAME=cpu_test_overflow
        set HEX_FILE=overflow_test.hex
        set SHADOW_BANKS=1
        set OVERFLOW_POLICY=0
    ) else if "%1"=="degradation" (
        set TEST_NAME=cpu_test_degradation
        set HEX_FILE=degradation_test.hex
        set SHADOW_BANKS=1
        set OVERFLOW_POLICY=1
    ) else if "%1"=="tailchain" (
        set TEST_NAME=cpu_test_tailchain
        set HEX_FILE=tail_chain_test.hex
    ) else if "%1"=="context" (
        set TEST_NAME=cpu_test_context
        set HEX_FILE=context_integrity_test.hex
    ) else (
        set HEX_FILE=%1
    )
)

REM 解析第二个参数 (GUI)
if not "%2"=="" (
    if "%2"=="gui" set GUI_MODE=1
)

echo ========================================
echo   FX-RV32 UVM Verification
echo ========================================
echo   TEST_NAME     : %TEST_NAME%
echo   HEX_FILE      : %HEX_FILE%
echo   GUI_MODE      : %GUI_MODE%
echo   SHADOW_BANKS  : %SHADOW_BANKS%
echo   OVERFLOW_POLICY: %OVERFLOW_POLICY%
echo ========================================

REM 启动 Modelsim
if %GUI_MODE%==1 (
    vsim -do "set HEX_FILE %HEX_FILE%; set TEST_NAME %TEST_NAME%; set GUI_MODE 1; set SHADOW_BANKS %SHADOW_BANKS%; set OVERFLOW_POLICY %OVERFLOW_POLICY%; do run_msim.tcl"
) else (
    vsim -c -do "set HEX_FILE %HEX_FILE%; set TEST_NAME %TEST_NAME%; set SHADOW_BANKS %SHADOW_BANKS%; set OVERFLOW_POLICY %OVERFLOW_POLICY%; do run_msim.tcl"
)

pause
