module systolic#(
    parameter ARRAY_SIZE = 8,
    parameter SRAM_DATA_WIDTH = 64,
    parameter DATA_WIDTH = 8,
    // --- 显式添加累加深度参数 ---
    parameter K_ACCUM_DEPTH = 32,  // 用户可配置的累加深度，默认为原始行为 (K=8)
    parameter DATA_SET = 1, //数据集的个数
    parameter OUTCOME_WIDTH = 32
)
(
    input clk,
    input srstn,
    input alu_start,
    input [8:0] cycle_num,     // 如果K_ACCUM_DEPTH非常大，可能需要更宽
    // input [5:0] data_set,

    input [SRAM_DATA_WIDTH-1:0] sram_rdata_w,
    // input [SRAM_DATA_WIDTH-1:0] sram_rdata_w1,

    input [7:0] sram_rdata_v,
    // input [SRAM_DATA_WIDTH-1:0] sram_rdata_d1,

    // input [5:0] matrix_index,
    // --- 根据新的OUTCOME_WIDTH调整输出总线宽度 ---
    output reg [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome
);

// localparam OUTCOME_WIDTH = DATA_WIDTH + DATA_WIDTH + $clog2(K_ACCUM_DEPTH) + 1;
// localparam OUTCOME_WIDTH = 32;

// --- 内部寄存器和线网声明 (使用新的 OUTCOME_WIDTH) ---
reg signed [DATA_WIDTH-1:0] weight_queue [0:ARRAY_SIZE-1]; // 数据矩阵
reg signed [OUTCOME_WIDTH-1:0] acc_reg [0:ARRAY_SIZE-1]; // 乘积结果矩阵

integer i;


always @(*) begin
    if (~srstn) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] = 0; // 初始化权重队列
        end
    end
    else if (alu_start) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] = sram_rdata_w[(63-8*i)-:8];
        end
    end
    else begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] = weight_queue[i]; // 保持旧值
        end
    end
end

always @(posedge clk) begin
    if(~srstn) begin
        for(i=0; i<ARRAY_SIZE; i=i+1) begin
            acc_reg[i] <= 0;
        end
    end
    else begin
        if(alu_start & cycle_num < K_ACCUM_DEPTH -1) begin
            // 累加器
            for(i=0; i<ARRAY_SIZE; i=i+1) begin
                acc_reg[i] <= acc_reg[i] + $signed(weight_queue[i]) * $signed(sram_rdata_v); // 使用sram_rdata_v的第0列数据
            end
        end
        else begin
            // 累加器保持旧值
            for(i=0; i<ARRAY_SIZE; i=i+1) begin
                acc_reg[i] <= acc_reg[i];
            end
        end
    end
end


//------output data: mul_outcome(indexed by matrix_index)------
// (输出逻辑本身不变，但 mul_outcome 的总宽度已在模块端口处更新)
always@(*) begin
    mul_outcome = 1'b0; // 默认输出为0
    
    for(i=0; i<ARRAY_SIZE; i=i+1) begin
        mul_outcome[((ARRAY_SIZE-i) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH] = acc_reg[i];
    end
end

endmodule