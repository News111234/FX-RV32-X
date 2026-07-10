######################################################################
# ʱ��Լ��
######################################################################

# 200MHz ���ʱ������Լ��
create_clock -name sys_clk -period 5.000 [get_ports {clk_p_i}]

# �����ӳ�Լ�����ɸ���ʵ����Ҫ������
set_input_delay -clock sys_clk -max 0 [get_ports {spi_miso_i}]
set_input_delay -clock sys_clk -min 0 [get_ports {spi_miso_i}]
set_input_delay -clock sys_clk -max 0 [get_ports {uart_rx_i}]
set_input_delay -clock sys_clk -min 0 [get_ports {uart_rx_i}]

# ����ӳ�Լ��
set_output_delay -clock sys_clk -max 0 [get_ports {uart_tx_o}]
set_output_delay -clock sys_clk -min 0 [get_ports {uart_tx_o}]

# UART/SPI/I2C 异步外设接口 — 不要求 200MHz IO 时序
set_false_path -to [get_ports {uart_tx_o}]
set_false_path -from [get_ports {uart_rx_i}]
set_false_path -to [get_ports {spi_sclk_o spi_mosi_o spi_cs_o}]
set_false_path -from [get_ports {spi_miso_i}]
set_false_path -to [get_ports {i2c_sda_io i2c_scl_io}]
set_false_path -from [get_ports {i2c_sda_io i2c_scl_io}]
# �첽��λ·��������ʱ���飩
#set_false_path -to [get_cells -hierarchical -filter {NAME =~ *rst_n_internal*}]

######################################################################
# ���ŷ���
######################################################################

# ========== ϵͳʱ�� ==========
# 200MHz ���ʱ�����루����ʵ��ԭ��ͼ�޸ģ�
set_property PACKAGE_PIN AD12 [get_ports clk_p_i]
set_property PACKAGE_PIN AD11 [get_ports clk_n_i]
set_property IOSTANDARD LVDS [get_ports {clk_p_i clk_n_i}]

# ========== UART ==========
set_property PACKAGE_PIN Y23 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
set_property SLEW FAST [get_ports uart_tx_o]
set_property DRIVE 8 [get_ports uart_tx_o]

# UART RX (Genesys 2 USB-UART FT2232)
set_property PACKAGE_PIN AB22 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]

# ========== SPI Flash (S25FL256S on Genesys 2) ==========
# SCK  - R23 (IO_L3P_T0_DQS_PUDC_B_14)
# MOSI - P24 (IO_L1P_T0_D00_MOSI_14)
# MISO - R25 (IO_L1N_T0_D01_DIN_14)
# CS   - R24 (IO_L3N_T0_DQS_EMCCLK_14)
set_property PACKAGE_PIN R23 [get_ports spi_sclk_o]
set_property PACKAGE_PIN P24 [get_ports spi_mosi_o]
set_property PACKAGE_PIN R25 [get_ports spi_miso_i]
set_property PACKAGE_PIN R24 [get_ports spi_cs_o]

set_property IOSTANDARD LVCMOS33 [get_ports {spi_sclk_o spi_mosi_o spi_miso_i spi_cs_o}]
set_property SLEW FAST [get_ports {spi_sclk_o spi_mosi_o spi_cs_o}]
set_property DRIVE 8 [get_ports {spi_sclk_o spi_mosi_o spi_cs_o}]

# ========== I2C �ӿ� ==========
# SDA - �����ߣ�˫����Ҫ��©�����
set_property PACKAGE_PIN Y16 [get_ports i2c_sda_io]
set_property IOSTANDARD LVCMOS18 [get_ports i2c_sda_io]
set_property SLEW FAST [get_ports i2c_sda_io]
set_property DRIVE 8 [get_ports i2c_sda_io]

# SCL - ʱ���ߣ�˫����Ҫ��©�����
set_property PACKAGE_PIN Y17 [get_ports i2c_scl_io]
set_property IOSTANDARD LVCMOS18 [get_ports i2c_scl_io]
set_property SLEW FAST [get_ports i2c_scl_io]
set_property DRIVE 8 [get_ports i2c_scl_io]

# ========== GPIO �ӿ� ==========
# GPIO 0-31������ʵ������������ţ�
# �������Ž���ʾ������Ҫ����ԭ��ͼ�޸�
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

# GPIO ��ƽ��׼
# set_property IOSTANDARD LVCMOS33 [get_ports {gpio_io[*]}]

# ========== LED ָʾ�� ==========
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
# �ۺ���ʵ��ѡ��
######################################################################

# ���� I2C ��©�������Ҫ���� PULLUP Ϊ TRUE
set_property PULLUP TRUE [get_ports i2c_sda_io]
set_property PULLUP TRUE [get_ports i2c_scl_io]

# ����δʹ�õ��ڲ��߼��Ż������ڵ��ԣ�
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]

# ������ϻ�·������У�
# set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical *]

######################################################################
# ʱ�����⣨����ʵ��������ӣ�
######################################################################

# ��ʱ����·��������ж��ʱ����
# set_clock_groups -asynchronous -group [get_clocks sys_clk]

# ������·����������������ӿڣ�
# set_multicycle_path -setup 2 -hold 1 -to [get_ports spi_miso_i]