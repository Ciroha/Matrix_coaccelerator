`timescale 1ns/100ps


`define cycle_period 10
//`define End_CYCLE  250000 
module test_tpu;

localparam DATA_WIDTH = 8;
localparam OUT_DATA_WIDTH = 16;
localparam SRAM_DATA_WIDTH = 64;
localparam ARRAY_SIZE = 8;
localparam K_ACCUM_DEPTH = 32;	//累加深度
localparam DATA_SET = 1;	//数据集的个数
// localparam OUTCOME_WIDTH = DATA_WIDTH + DATA_WIDTH + $clog2(K_ACCUM_DEPTH) + 1; //计算输出宽度
localparam OUTCOME_WIDTH = 32;
localparam FILENAME   = "memory_dump.txt";

//====== module I/O =====
reg clk;
reg srstn;
reg tpu_start;

wire tpu_finish;


wire sram_write_enable_a0;
wire sram_write_enable_a1;


wire sram_write_enable_b0;
wire sram_write_enable_b1;


wire sram_write_enable_c0;

wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w;

wire [7:0] sram_rdata_v;


wire [5:0] sram_raddr_w;
wire [4:0] sram_raddr_v;


wire [5:0] sram_raddr_c0;
wire [5:0] sram_raddr_c1;
wire [5:0] sram_raddr_c2;

wire [3:0] sram_bytemask_a;
wire [3:0] sram_bytemask_b;
wire [9:0] sram_waddr_a;
wire [9:0] sram_waddr_b;
wire [7:0] sram_wdata_a;
wire [7:0] sram_wdata_b;

wire [DATA_WIDTH*OUT_DATA_WIDTH-1:0] sram_wdata_c0;

wire [DATA_WIDTH*OUT_DATA_WIDTH-1:0] sram_rdata_c0;

wire [5:0] sram_waddr_c0;



wire signed [7:0] out;
wire [ARRAY_SIZE * OUTCOME_WIDTH - 1:0] mul_outcome;
reg [OUTCOME_WIDTH-1:0] memory [0:ARRAY_SIZE-1];


//reg [7:0] mem[0:32*32-1];


//====== top connection =====

tpu_top #(
	.ARRAY_SIZE(ARRAY_SIZE),
	.SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
	.DATA_WIDTH(DATA_WIDTH),
	.OUTPUT_DATA_WIDTH(OUT_DATA_WIDTH),
	.K_ACCUM_DEPTH(K_ACCUM_DEPTH),       //与systolic模块同步的累加深度
	.DATA_SET(DATA_SET)          //数据集的个数
)
my_tpu_top(
	.clk(clk),
	.srstn(srstn),
	.tpu_start(tpu_start),

	//input data
	.sram_rdata_w(sram_rdata_w),

	.sram_rdata_v(sram_rdata_v),

	//output weight
	.sram_raddr_w(sram_raddr_w),
	.sram_raddr_v(sram_raddr_v),

	//write to the SRAM for comparision
	.sram_write_enable_a0(sram_write_enable_c0),
	.sram_wdata_a(sram_wdata_c0),
	.sram_waddr_a(sram_waddr_c0),
	.mul_outcome(mul_outcome),

	.tpu_done(tpu_finish)
);

//weight_read
sram_64x64b sram_64x64b_w(
.clk(clk),
.csb(1'b0),
.wsb(1'b1),	//禁止写使能
.wdata(64'b0),
.waddr(6'b0),
.raddr(sram_raddr_w),
.rdata(sram_rdata_w)
);

sram_32x8b sram_32x8b_v(
.clk(clk),
.csb(1'b0),
.wsb(1'b1),	//禁止写使能
.wdata(8'b0),
.waddr(5'b0),
.raddr(sram_raddr_v),
.rdata(sram_rdata_v)
);


//write sram
sram_16x128b sram_16x128b_c0(
.clk(clk),
.csb(1'b0),
.wsb(sram_write_enable_c0),
.wdata(sram_wdata_c0), 
.waddr(sram_waddr_c0), 
.raddr(sram_raddr_c0), 
.rdata(sram_rdata_c0)
);



//dump wave file
// initial begin
//   $fsdbDumpfile("tpu.fsdb"); // "gray.fsdb" can be replaced into any name you want
//   $fsdbDumpvars("+mda");              // but make sure in .fsdb format
// end

//====== clock generation =====
initial begin
    srstn = 1'b1;
    clk = 1'b1;
    #(`cycle_period/2);
    while(1) begin
      #(`cycle_period/2) clk = ~clk; 
    end
end

//====== main procedural block for simulation =====
integer cycle_cnt;


integer i,j;
reg [7:0] weights_mat[0:K_ACCUM_DEPTH*ARRAY_SIZE-1];
// reg [7:0] skew_weights_mat[0:(K_ACCUM_DEPTH+ARRAY_SIZE-1)*ARRAY_SIZE-1];
reg [7:0] vectors[0:K_ACCUM_DEPTH-1];

initial begin
    // $dumpfile("waveform.vcd");
    // $dumpvars(0, test_tpu);
    // $fsdbDumpfile("waveform.fsdb"); // 指定FSDB文件名
    // $fsdbDumpvars(0, test_tpu);      // 0表示dump test_tpu模块下的所有信号
    // $fsdbDumpMDA;

	$readmemh("weights.txt", weights_mat);
	$readmemh("vector.txt", vectors);

    #(`cycle_period);

    init;
	data2sram_new;
        
    tpu_start = 1'b0;
    cycle_cnt = 0;
    @(negedge clk);
    srstn = 1'b0;
    @(negedge clk);
    srstn = 1'b1;
    tpu_start = 1'b1;  //one-cycle pulse signal  
    @(negedge clk);
    tpu_start = 1'b0;
    while(~tpu_finish)begin    //it's mean that your sram c0, c1, c2 can be tested
        @(negedge clk);     begin
            cycle_cnt = cycle_cnt + 1;
        end
    end

	write_out;
    //TODO cycle_cnt逻辑有点问题
    // $display("Total cycle count C after three matrix evaluation = %d.", cycle_cnt);
    #5 $finish;
end


task init;
begin
	for(i=0; i<64; i = i + 1) begin
		sram_64x64b_w.load(i, 64'b0);
	end
	for(i=0; i<32; i = i + 1) begin
		sram_32x8b_v.load(i, 8'b0);
	end
end
endtask


task data2sram_new;
begin
    // // 创建倾斜权重矩阵
    // for(i = 0; i < (K_ACCUM_DEPTH + ARRAY_SIZE - 1) * ARRAY_SIZE; i = i + 1) begin
    //     skew_weights_mat[i] = 8'b0; // 初始化为0
    // end
    
    // // 填充权重数据，每隔32个数插入8个0
    // for(i = 0; i < ARRAY_SIZE; i = i + 1) begin  // 8行
    //     for(j = 0; j < K_ACCUM_DEPTH; j = j + 1) begin  // 每行32个有效数据
    //         // 计算在倾斜矩阵中的位置：行偏移 + 列位置
    //         skew_weights_mat[i * (K_ACCUM_DEPTH + ARRAY_SIZE -1) + i + j] = weights_mat[i * K_ACCUM_DEPTH + j];
    //     end
    // end
	// 将倾斜矩阵加载到sram_64x64b_w
	for(i = 0; i < 32; i = i + 1) begin
		sram_64x64b_w.load(i, {weights_mat[0*(K_ACCUM_DEPTH) + i], weights_mat[1*(K_ACCUM_DEPTH) + i], weights_mat[2*(K_ACCUM_DEPTH) + i], weights_mat[3*(K_ACCUM_DEPTH) + i], weights_mat[4*(K_ACCUM_DEPTH) + i], weights_mat[5*(K_ACCUM_DEPTH) + i], weights_mat[6*(K_ACCUM_DEPTH) + i], weights_mat[7*(K_ACCUM_DEPTH) + i]});
	end
	for(i = 0; i < 32; i = i + 1)begin
		sram_32x8b_v.load(i, vectors[i]);
	end
	
	//display
	// $write("SRAM A is for weight\n");
	// for(i = 0; i < 8 ; i = i + 1) begin
	// 	for(j = 0; j < 64; j = j + 1) begin
	// 		$write("%d ", $signed(sram_64x64b_w.mem[j][(63-8*i)-:8]));
	// 	end
    // $write("\n");
	// end
	// sram_64x64b_w.display();
	// $write("SRAM B is for data\n");
    // for(j = 0; j < 32; j = j + 1) begin
	// 	$write("%d ", $signed(sram_32x8b_v.mem[j]));
	// end
	// $write("\n");
end
endtask

task write_out;
begin
	for(i = 0; i < ARRAY_SIZE; i = i + 1) begin
		memory[i] = mul_outcome[(OUTCOME_WIDTH*(ARRAY_SIZE-i)-1) -: OUTCOME_WIDTH];
	end
	// $display("Memory[0] = %h", memory[0]);
    // $display("Memory[1] = %h", memory[1]);
    // $display("Memory[2] = %h", memory[2]);
	// $display("Writing memory contents to file: %s", FILENAME);
    $writememh(FILENAME, memory);
	// $display("Write operation complete. Check the output file.");
end
endtask

endmodule
