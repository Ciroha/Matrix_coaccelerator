///////////////////////////
module sram_32x8b(
input clk,
input csb,  //chip enable
input wsb,  //write enable
input [7:0] wdata, //write data
input [4:0] waddr, //write address
input [4:0] raddr, //read address

output reg [7:0]rdata //read data
);

reg [7:0] mem[0:31];
reg [7:0] _rdata;

always@(posedge clk)
  if(~csb && ~wsb)
    mem[waddr] <= wdata;

always@(posedge clk)
  if(~csb)
    _rdata <= mem[raddr];

always@*
begin
    rdata =  _rdata;
end


task load(
    input integer index,
    input [7:0] weight_input
);
    mem[index] = weight_input;
endtask

task display();
integer i;
for (i = 0;i < 32 ;i = i + 1 ) begin
  $display("%b",mem[i]);
end
endtask

endmodule
