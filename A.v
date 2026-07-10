//1、	分别描述一个单bit脉冲从快时钟到慢时钟的跨异步同步、慢时钟到快时钟的跨异步同步。
//快慢时钟分别为100M和25M
module test(        
    input src_clk,
    input dst_clk,
    input rst_n,
    input src_sig,
    output dst_sig

);


reg sig_d1,sig_d2;
always @(posedge dst_clk or negedge rst_n)  begin
    if(!rst_n) {sig_d2,sig_d1} <=0;
    else {sig_d2,sig_d1} <= {sig_d1,src_sig};
end
assign dst_sig =sig_d2;
endmodule