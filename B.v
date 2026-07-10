//快到慢多比特  快:100m 慢：25m   //面试官说格雷码的使用场景是多比特同步，减少亚稳态的概率
module Duo_bit (

          input clk_fast,
          input clk_slow,
          input rst_n,
          input  [4:0]cnt,
          output [4:0] bit_cnt_sync

);
reg [4:0] gray_reg ,gray_sync1,gray_sync2;
//二进制转格雷码

//慢同步
always @(posedge clk_slow or negedge rst_n) begin
    if(!rst_n) {gray_sync2,gray_sync1} <= 0;
    else {gray_sync2,gray_sync1} <= {gray_sync1,gray_reg};
end

//edge detect
reg [4:0] gray_sync2_d;
always @(posedge clk_slow or negedge rst_n) begin
    if(!rst_n) gray_sync2_d <= 0;
    else gray_sync2_d <= gray_sync2;
end

wire [4:0] gray_sync2_edge = gray_sync2 ^ gray_sync2_d;
//格雷码转二进制
reg [4:0] bit_cnt_sync_reg;
integer i;
always @(*) begin
    bit_cnt_sync_reg[4] = gray_sync2_edge[4];
    for(i=3;i>=0;i=i-1) begin
        bit_cnt_sync_reg[i] = gray_sync2_edge[i] ^ bit_cnt_sync_reg[i+1];
    end
end

assign bit_cnt_sync = bit_cnt_sync_reg;
endmodule