  1. Bootloader + 外部 Flash：inst_rom 里只放一个小的 bootloader，上电后从 SPI Flash 加载真正程序到
  data_ram，然后跳转执行
  2. JTAG 调试器：通过调试接口直接把程序写到 data_ram
  3. UART boot：和 bootloader 类似，从 UART 接收程序
