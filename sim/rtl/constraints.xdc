######################################################################
# 时钟约束
######################################################################

# 200MHz 差分时钟输入约束
create_clock -name sys_clk -period 5.000 [get_ports {clk_p_i}]

# 输入延迟约束（可根据实际需要调整）
set_input_delay -clock sys_clk -max 2 [get_ports {spi_miso_i}]
set_input_delay -clock sys_clk -min 0.5 [get_ports {spi_miso_i}]

# 输出延迟约束
set_output_delay -clock sys_clk -max 2 [get_ports {uart_tx_o}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {uart_tx_o}]

# 异步复位路径（忽略时序检查）
#set_false_path -to [get_cells -hierarchical -filter {NAME =~ *rst_n_internal*}]

######################################################################
# 引脚分配
######################################################################

# ========== 系统时钟 ==========
# 200MHz 差分时钟输入（根据实际原理图修改）
set_property PACKAGE_PIN AD12 [get_ports clk_p_i]
set_property PACKAGE_PIN AD11 [get_ports clk_n_i]
set_property IOSTANDARD LVDS [get_ports {clk_p_i clk_n_i}]

# ========== UART ==========
# 根据实际原理图修改引脚号
set_property PACKAGE_PIN Y23 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
set_property SLEW FAST [get_ports uart_tx_o]
set_property DRIVE 8 [get_ports uart_tx_o]

# ========== SPI 接口 ==========
# SCLK - SPI时钟
#set_property PACKAGE_PIN AA18 [get_ports spi_sclk_o]
#set_property IOSTANDARD LVCMOS33 [get_ports spi_sclk_o]
#set_property SLEW FAST [get_ports spi_sclk_o]
#set_property DRIVE 8 [get_ports spi_sclk_o]

# MOSI - 主出从入
# set_property PACKAGE_PIN AB17 [get_ports spi_mosi_o]
# set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi_o]
# set_property SLEW FAST [get_ports spi_mosi_o]
# set_property DRIVE 8 [get_ports spi_mosi_o]

# MISO - 主入从出
# set_property PACKAGE_PIN AB18 [get_ports spi_miso_i]
# set_property IOSTANDARD LVCMOS33 [get_ports spi_miso_i]

# CS - 片选（低有效）
# set_property PACKAGE_PIN AC18 [get_ports spi_cs_o]
# set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_o]
# set_property SLEW FAST [get_ports spi_cs_o]
# set_property DRIVE 8 [get_ports spi_cs_o]

# ========== I2C 接口 ==========
# SDA - 数据线（双向，需要开漏输出）
# set_property PACKAGE_PIN Y16 [get_ports i2c_sda_io]
# set_property IOSTANDARD LVCMOS33 [get_ports i2c_sda_io]
# set_property SLEW FAST [get_ports i2c_sda_io]
# set_property DRIVE 8 [get_ports i2c_sda_io]

# SCL - 时钟线（双向，需要开漏输出）
# set_property PACKAGE_PIN Y17 [get_ports i2c_scl_io]
# set_property IOSTANDARD LVCMOS33 [get_ports i2c_scl_io]
# set_property SLEW FAST [get_ports i2c_scl_io]
# set_property DRIVE 8 [get_ports i2c_scl_io]

# ========== GPIO 接口 ==========
# GPIO 0-31（根据实际需求分配引脚）
# 以下引脚仅作示例，需要根据原理图修改
# set_property PACKAGE_PIN AA20 [get_ports {gpio_io[0]}]
# set_property PACKAGE_PIN AB20 [get_ports {gpio_io[1]}]
# set_property PACKAGE_PIN AC20 [get_ports {gpio_io[2]}]
# set_property PACKAGE_PIN AD20 [get_ports {gpio_io[3]}]
# set_property PACKAGE_PIN AA19 [get_ports {gpio_io[4]}]
# set_property PACKAGE_PIN AB19 [get_ports {gpio_io[5]}]
# set_property PACKAGE_PIN AC19 [get_ports {gpio_io[6]}]
# set_property PACKAGE_PIN AD19 [get_ports {gpio_io[7]}]
# set_property PACKAGE_PIN AA21 [get_ports {gpio_io[8]}]
# set_property PACKAGE_PIN AB21 [get_ports {gpio_io[9]}]
# set_property PACKAGE_PIN AC21 [get_ports {gpio_io[10]}]
# set_property PACKAGE_PIN AD21 [get_ports {gpio_io[11]}]
# set_property PACKAGE_PIN AA22 [get_ports {gpio_io[12]}]
# set_property PACKAGE_PIN AB22 [get_ports {gpio_io[13]}]
# set_property PACKAGE_PIN AC22 [get_ports {gpio_io[14]}]
# set_property PACKAGE_PIN AD22 [get_ports {gpio_io[15]}]
# set_property PACKAGE_PIN AA23 [get_ports {gpio_io[16]}]
# set_property PACKAGE_PIN AB23 [get_ports {gpio_io[17]}]
# set_property PACKAGE_PIN AC23 [get_ports {gpio_io[18]}]
# set_property PACKAGE_PIN AD23 [get_ports {gpio_io[19]}]
# set_property PACKAGE_PIN AA24 [get_ports {gpio_io[20]}]
# set_property PACKAGE_PIN AB24 [get_ports {gpio_io[21]}]
# set_property PACKAGE_PIN AC24 [get_ports {gpio_io[22]}]
# set_property PACKAGE_PIN AD24 [get_ports {gpio_io[23]}]
# set_property PACKAGE_PIN AA25 [get_ports {gpio_io[24]}]
# set_property PACKAGE_PIN AB25 [get_ports {gpio_io[25]}]
# set_property PACKAGE_PIN AC25 [get_ports {gpio_io[26]}]
# set_property PACKAGE_PIN AD25 [get_ports {gpio_io[27]}]
# set_property PACKAGE_PIN AA26 [get_ports {gpio_io[28]}]
# set_property PACKAGE_PIN AB26 [get_ports {gpio_io[29]}]
# set_property PACKAGE_PIN AC26 [get_ports {gpio_io[30]}]
# set_property PACKAGE_PIN AD26 [get_ports {gpio_io[31]}]

# GPIO 电平标准
# set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[*]}]

# ========== LED 指示灯 ==========
set_property PACKAGE_PIN T28 [get_ports led0_o]
set_property PACKAGE_PIN V19 [get_ports led1_o]
set_property PACKAGE_PIN U30 [get_ports led2_o]
set_property PACKAGE_PIN U29 [get_ports led3_o]
set_property PACKAGE_PIN V20 [get_ports led4_o]
set_property PACKAGE_PIN V26 [get_ports led5_o]
set_property PACKAGE_PIN W24 [get_ports led6_o]
set_property PACKAGE_PIN W23 [get_ports led7_o]

set_property IOSTANDARD LVCMOS33 [get_ports {led0_o led1_o led2_o led3_o led4_o led5_o led6_o led7_o}]
set_property SLEW FAST [get_ports {led0_o led1_o led2_o led3_o led4_o led5_o led6_o led7_o}]
set_property DRIVE 8 [get_ports {led0_o led1_o led2_o led3_o led4_o led5_o led6_o led7_o}]

######################################################################
# 综合与实现选项
######################################################################

# 对于 I2C 开漏输出，需要设置 PULLUP 为 TRUE
set_property PULLUP TRUE [get_ports i2c_sda_io]
set_property PULLUP TRUE [get_ports i2c_scl_io]

# 禁用未使用的内部逻辑优化（便于调试）
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]

# 允许组合环路（如果有）
# set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *]

######################################################################
# 时序例外（根据实际情况添加）
######################################################################

# 跨时钟域路径（如果有多个时钟域）
# set_clock_groups -asynchronous -group [get_clocks sys_clk]

# 多周期路径（对于慢速外设接口）
# set_multicycle_path -setup 2 -hold 1 -to [get_ports spi_miso_i]