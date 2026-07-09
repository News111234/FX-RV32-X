// RTL 源文件列表 (Modelsim/Questa 编译顺序)
// 顶层: uvm_tb_top.sv (单独用 -sv 编译)

// ==== core — CPU 核心 ====
../core/ifu/pc_reg.v
../core/ifu/ifu_top.v
../core/id/decoder.v
../core/id/ctrl.v
../core/id/imm_gen.v
../core/id/regfile.v
../core/id/id_top.v
../core/exu/alu.v
../core/exu/branch.v
../core/exu/ex_top.v
../core/mem/mem_ctrl.v
../core/mem/mem_top.v
../core/wbu/wb_mux.v
../core/wbu/wb_top.v
../core/pipeline/if_id_reg.v
../core/pipeline/id_ex_reg.v
../core/pipeline/ex_mem_reg.v
../core/pipeline/mem_wb_reg.v
../core/hazard/hazard_unit.v
../core/hazard/forwarding_unit.v
../core/csr/csr_regfile.v
../core/csr/csr_instructions.v
../core/interrupt/interrupt_controller.v
../core/interrupt/interrupt_pipeline.v
../core/core_top.v

// ==== soc — SoC 集成 ====
../soc/mem/inst_bram.v
../soc/mem/data_ram.v
../soc/bus/bus_arbiter.v
../soc/periph/uart_tx.v
../soc/periph/uart_rx.v
../soc/periph/uart_ctrl.v
../soc/periph/gpio.v
../soc/periph/timer.v
../soc/periph/spi_master.v
../soc/periph/spi_flash_ctrl.v
../soc/periph/i2c_master.v
../soc/top/soc_top.v
