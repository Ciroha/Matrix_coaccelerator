///////////////////////////
module sram_64x64b(
input clk,
input csb,  //chip enable
input wsb,  //write enable
input [63:0] wdata, //write data
input [5:0] waddr, //write address
input [5:0] raddr, //read address

output reg [63:0]rdata //read data
);

reg [63:0] mem[0:63];
reg [63:0] _rdata;

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
    input [63:0] weight_input
);
    mem[index] = weight_input;
endtask

task display();
integer i;
for (i = 0;i < 64 ;i = i + 1 ) begin
  $display("%h",mem[i]);
end
endtask

endmodule
