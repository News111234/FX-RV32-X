// nested_uvm/cpu_if.sv — UVM接口（soctop专用, 精简版）
`timescale 1ns/1ps

interface cpu_if (
    input wire clk,
    input wire rst_n
);
    // GPIO (testbench驱动, 用于触发外部中断)
    logic        gpio_pin0;

    // 软件中断 (testbench驱动, 用于三级嵌套)
    logic        intr_software;

    // 监控信号 (来自soc_top内部, 通过层次路径访问)
    // 注: 以下信号在tb_top中用assign连接到DUT内部

    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output gpio_pin0;
        output intr_software;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #3ns;
        input gpio_pin0;
    endclocking

endinterface
