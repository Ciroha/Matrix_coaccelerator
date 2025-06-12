//-------do the address select for 32 queue, each queue size 32+32-1---


module addr_sel
(
	input clk,
	input [5:0] addr_serial_num,							//max = 126, setting all of the addr127 = 0
	
	//sel for w0~w7
	output reg [5:0] sram_raddr_w,		//queue 0~3

	//sel for d0~d7
	output reg [4:0] sram_raddr_v
);

wire [5:0] sram_raddr_w_nx;			//queue 0~3
wire [4:0] sram_raddr_v_nx;

always@(posedge clk) begin				//fit in output flip-flop
	sram_raddr_w <= sram_raddr_w_nx;
	sram_raddr_v <= sram_raddr_v_nx;
end

assign sram_raddr_w_nx = addr_serial_num[5:0];
assign sram_raddr_v_nx = addr_serial_num[4:0];

endmodule
