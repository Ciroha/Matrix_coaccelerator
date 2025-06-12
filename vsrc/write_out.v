//-----this module is for writing data out------

module write_out#(
	parameter ARRAY_SIZE = 8,
	parameter OUTPUT_DATA_WIDTH = 16,
	parameter K_ACCUM_DEPTH = 8
)
(
	input clk,
	input srstn,
	input sram_write_enable,

	input [5:0] data_set,
	// input [5:0] matrix_index,
	input [8:0] cycle_num,

	input signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data,
	
	output reg sram_write_enable_a0,
	output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
 	output reg [5:0] sram_waddr_a

	// output reg sram_write_enable_b0,
	// output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b,
 	// output reg [5:0] sram_waddr_b,

	// output reg sram_write_enable_c0,
	// output reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c,
 	// output reg [5:0] sram_waddr_c
);

integer i;

//output flip-flop
reg sram_write_enable_a0_nx;
reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a_nx;
reg [5:0] sram_waddr_a_nx;

// reg sram_write_enable_b0_nx;
// reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b_nx;
// reg [5:0] sram_waddr_b_nx;

// reg sram_write_enable_c0_nx;
// reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c_nx;
// reg [5:0] sram_waddr_c_nx;

//---sequential logic-----
always@(posedge clk) begin
	if(~srstn) begin
		sram_write_enable_a0 <= 1;
		sram_wdata_a <= 0;
		sram_waddr_a <= 0;

		// sram_write_enable_b0 <= 1;
		// sram_wdata_b <= 0;
		// sram_waddr_b <= 0;

		// sram_write_enable_c0 <= 1;
		// sram_wdata_c <= 0;
		// sram_waddr_c <= 0;
	end
	else begin
		sram_write_enable_a0 <= sram_write_enable_a0_nx;
		sram_wdata_a <= sram_wdata_a_nx;
		sram_waddr_a <= sram_waddr_a_nx;

		// sram_write_enable_b0 <= sram_write_enable_b0_nx;
		// sram_wdata_b <= sram_wdata_b_nx;
		// sram_waddr_b <= sram_waddr_b_nx;

		// sram_write_enable_c0 <= sram_write_enable_c0_nx;
		// sram_wdata_c <= sram_wdata_c_nx;		
		// sram_waddr_c <= sram_waddr_c_nx;
	end
end

//写入a逻辑
always@(*) begin
	if(sram_write_enable) begin
		case(data_set)
			0: begin
				if(cycle_num > K_ACCUM_DEPTH && cycle_num <= K_ACCUM_DEPTH + ARRAY_SIZE) begin
					sram_write_enable_a0_nx = 0;
					sram_wdata_a_nx = quantized_data;
					sram_waddr_a_nx = cycle_num - K_ACCUM_DEPTH -1;
				end
				else begin
					sram_write_enable_a0_nx = 1;
					for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
						sram_wdata_a_nx[i] = 0;
					sram_waddr_a_nx = 0;
				end
			end
		
			default: begin
				sram_write_enable_a0_nx = 1;
				for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
					sram_wdata_a_nx[i] = 0;
				sram_waddr_a_nx = 0;
			end
		endcase
	end
	else begin
		sram_write_enable_a0_nx = 1;
		for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
			sram_wdata_a_nx[i] = 0;
		sram_waddr_a_nx = 0;
	end
end

// //写入b逻辑
// always@(*) begin
// 	if(sram_write_enable) begin
// 		case(data_set)
// 			1: begin
// 				if(cycle_num < ARRAY_SIZE) begin	//TODO To be fixed
// 					sram_write_enable_b0_nx = 0;
// 					sram_wdata_b_nx = quantized_data;
// 					sram_waddr_b_nx = cycle_num;
// 				end
// 				else begin														//mix type
// 					sram_write_enable_b0_nx = 1;
// 					for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 						sram_wdata_b_nx[i] = 0;
// 					sram_waddr_b_nx = 0;
// 				end
// 			end

// 			default: begin
// 				sram_write_enable_b0_nx = 1;
// 				for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 					sram_wdata_b_nx[i] = 0;
// 				sram_waddr_b_nx = 0;
// 			end
// 		endcase
// 	end
// 	else begin
// 		sram_write_enable_b0_nx = 1;
// 		for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 			sram_wdata_b_nx[i] = 0;
// 		sram_waddr_b_nx = 0;
// 	end
// end

// //写入c逻辑
// always@(*) begin
// 	if(sram_write_enable) begin
// 		case(data_set)
// 			2: begin
// 				if(cycle_num < ARRAY_SIZE) begin
// 					sram_write_enable_c0_nx = 0;
// 					sram_wdata_c_nx = quantized_data;
// 					sram_waddr_c_nx = cycle_num;
// 				end
// 				else begin
// 					sram_write_enable_c0_nx = 1;
// 					for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 						sram_wdata_c_nx[i] = 0;
// 					sram_waddr_c_nx = 0;
// 				end
// 			end

// 			default: begin
// 				sram_write_enable_c0_nx = 1;
// 				for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 					sram_wdata_c_nx[i] = 0;
// 				sram_waddr_c_nx = 0;
// 			end
// 		endcase
// 	end
// 	else begin
// 		sram_write_enable_c0_nx = 1;
// 		for(i=0; i<ARRAY_SIZE*OUTPUT_DATA_WIDTH; i=i+1) 
// 			sram_wdata_c_nx[i] = 0;
// 		sram_waddr_c_nx = 0;
// 	end
// end

endmodule

