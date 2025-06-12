//------- ori data is from systolic array's mul_outcome, output to quantized data -------
//两个q4_4相乘并累加得到20位的数，将20位的数截断为q8_8
module quantize#(
    parameter ARRAY_SIZE = 8,
    parameter DATA_WIDTH = 8,
    parameter K_ACCUM_DEPTH = 8,       // <--- 新增: 与systolic模块同步的累加深度
    parameter OUTPUT_DATA_WIDTH = 16   // <--- 输出数据的位宽
)
(
    // 输入 ori_data 的总位宽需要与 systolic 模块的 mul_outcome 总位宽匹配
    // 单个原始数据元素的位宽 ORI_WIDTH 的计算方式如下：
    // DATA_WIDTH + DATA_WIDTH + (K_ACCUM_DEPTH == 1 ? 0 : $clog2(K_ACCUM_DEPTH)) + 1
    input signed [(ARRAY_SIZE * (DATA_WIDTH + DATA_WIDTH + ((K_ACCUM_DEPTH == 1) ? 0 : $clog2(K_ACCUM_DEPTH)) + 1)) - 1:0] ori_data,
    output reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data
);

// --- 根据输入参数动态计算单个原始数据元素的位宽 ---
localparam ACCUMULATOR_HEADROOM_ORI = (K_ACCUM_DEPTH == 1) ? 0 : $clog2(K_ACCUM_DEPTH);
localparam ORI_WIDTH = DATA_WIDTH + DATA_WIDTH + ACCUMULATOR_HEADROOM_ORI + 1;

// --- 根据 OUTPUT_DATA_WIDTH 参数化饱和值 ---
// 例如, OUTPUT_DATA_WIDTH = 16 -> max_val = 32767, min_val = -32768
// 例如, OUTPUT_DATA_WIDTH = 8  -> max_val = 127,   min_val = -128
localparam max_val = (1 << (OUTPUT_DATA_WIDTH - 1)) - 1; // 2^(N-1) - 1
localparam min_val = -(1 << (OUTPUT_DATA_WIDTH - 1));   // -2^(N-1)

reg signed [ORI_WIDTH-1:0] current_ori_element; // 用于暂存当前处理的原始数据元素

integer i;

// 量化逻辑：将ORI_WIDTH位的数据饱和到OUTPUT_DATA_WIDTH位表示的范围内，
// 然后截取/转换为OUTPUT_DATA_WIDTH位。
// 注意：此逻辑是饱和和截取LSBs。
// 如果需要特定的定点格式转换 (例如 Qm1.n1 -> Qm2.n2)，则需要更复杂的移位和舍入逻辑。
always@* begin
    for(i=0; i<ARRAY_SIZE; i=i+1) begin
        current_ori_element = ori_data[i*ORI_WIDTH +: ORI_WIDTH];

        if(current_ori_element >= max_val) begin
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = max_val;
        end
        else if(current_ori_element <= min_val) begin
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = min_val;
        end
        else begin
            // 如果原始数据在目标范围内，则截取其低 OUTPUT_DATA_WIDTH 位。
            // 这假设原始数据的最低位与目标量化数据的最低位对齐，
            // 或者这里隐式地进行了截断。
            // 对于真正的定点量化，这里可能需要右移（如果小数位数减少）
            // 或左移（如果小数位数增加，但不常见于这种直接截取）。
            // 当前行为：直接取低位。
            quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = current_ori_element[OUTPUT_DATA_WIDTH-1:0];
        end
    end
end

endmodule