module tpu_top#(
	parameter ARRAY_SIZE = 8,
	parameter SRAM_DATA_WIDTH = 64,
	parameter DATA_WIDTH = 8,
	parameter OUTPUT_DATA_WIDTH = 16,
	parameter K_ACCUM_DEPTH = 8,   // 用户可配置的累加深度，默认为原始行为 (K=8)
	parameter DATA_SET = 1,          //数据集的个数
	parameter OUTCOME_WIDTH = 32	 // 输出结果的宽度
)
(
	input clk,
	input srstn,
	input tpu_start,

	//input data for (data, weight) from eight SRAM
	input [SRAM_DATA_WIDTH-1:0] sram_rdata_w,
	
	input [7:0] sram_rdata_v,

	//output addr for (data, weight) from eight SRAM
	output [5:0] sram_raddr_w,

	output [4:0] sram_raddr_v,
	
	//write to three SRAN for comparison
	output sram_write_enable_a0,
	output [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
	output [5:0] sram_waddr_a,
	output [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome,
	
	output tpu_done
);
localparam ORI_WIDTH = DATA_WIDTH+DATA_WIDTH+5;
// localparam OUTCOME_WIDTH = DATA_WIDTH + DATA_WIDTH + $clog2(K_ACCUM_DEPTH) + 1;
// localparam OUTCOME_WIDTH = 32;

//----addr_sel parameter----
wire [5:0] addr_serial_num;

//----quantized parameter----
// wire signed [(ARRAY_SIZE * (DATA_WIDTH + DATA_WIDTH + ((K_ACCUM_DEPTH == 1) ? 0 : $clog2(K_ACCUM_DEPTH)) + 1)) - 1:0] ori_data;
// wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data;

//-----systolic parameter----
wire alu_start;
wire [8:0] cycle_num;
wire [5:0] matrix_index;

//----ststolic_controll parameter---
wire sram_write_enable;
// wire [5:0] data_set;	//TODO 适配更多的连续累加

//----write_out parameter----
// nothing XD



//----addr_sel module----
addr_sel addr_sel 
(
	//input
	.clk(clk),
	.addr_serial_num(addr_serial_num),	

	//output
	.sram_raddr_w(sram_raddr_w),

	.sram_raddr_v(sram_raddr_v)
);

//----quantize module----
// quantize #(
// 	.ARRAY_SIZE(ARRAY_SIZE),
// 	.DATA_WIDTH(DATA_WIDTH),
// 	.K_ACCUM_DEPTH(K_ACCUM_DEPTH),       // <--- 新增: 与systolic模块同步的累加深度
// 	.OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
// ) quantize
// (
// 	//input
// 	.ori_data(ori_data),

// 	//output
// 	.quantized_data(quantized_data)	
// );

//----systolic module----
systolic #(
	.ARRAY_SIZE(ARRAY_SIZE),
	.SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
	.DATA_WIDTH(DATA_WIDTH),
	.K_ACCUM_DEPTH(K_ACCUM_DEPTH),
	.OUTCOME_WIDTH(OUTCOME_WIDTH)
) systolic
(
	//input
	.clk(clk),
	.srstn(srstn),
	.alu_start(alu_start),
	.cycle_num(cycle_num),
	// .data_set(data_set),

	.sram_rdata_w(sram_rdata_w),	//每列4个数据，两列同时读
	.sram_rdata_v(sram_rdata_v), 	//每列4个数据，两列同时读

	// .matrix_index(matrix_index),
	
	//output
	.mul_outcome(mul_outcome)
);

//----systolic_controller module----
systolic_controll  #(
	.ARRAY_SIZE(ARRAY_SIZE),
	.K_ACCUM_DEPTH(K_ACCUM_DEPTH),
	.DATA_SET(DATA_SET) //数据集的个数
) systolic_controll
(
	//input
	.clk(clk),
	.srstn(srstn),
	.tpu_start(tpu_start),

	//output
	.sram_write_enable(sram_write_enable),
	.addr_serial_num(addr_serial_num),
	.alu_start(alu_start),
	.cycle_num(cycle_num),
	.matrix_index(matrix_index),
	// .data_set(data_set),
	.tpu_done(tpu_done)
);

//----write_out module----
write_out #(
	.ARRAY_SIZE(ARRAY_SIZE),
	.OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
	.K_ACCUM_DEPTH(K_ACCUM_DEPTH)
) write_out
(
	//input
	.clk(clk), 
	.srstn(srstn),
	.sram_write_enable(sram_write_enable),
	.data_set(data_set),
	// .matrix_index(matrix_index),
	.cycle_num(cycle_num),
	.quantized_data(quantized_data),

	//output
	.sram_write_enable_a0(sram_write_enable_a0),
	.sram_wdata_a(sram_wdata_a),
	.sram_waddr_a(sram_waddr_a)

	// .sram_write_enable_b0(sram_write_enable_b0),
	// .sram_wdata_b(sram_wdata_b),
	// .sram_waddr_b(sram_waddr_b),

	// .sram_write_enable_c0(sram_write_enable_c0),
	// .sram_wdata_c(sram_wdata_c),
	// .sram_waddr_c(sram_waddr_c)
);

endmodule

