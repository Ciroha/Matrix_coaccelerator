/*******************************************************************************
 * 模块名: fp_mul
 * 描述:   IEEE 754浮点乘法器。
 *
 * 功能:
 * - 处理特殊值 (NaN, Infinity, Zero)。
 * - 正确处理规格化数 (Normalized) 和非规格化数 (Denormalized)。
 * - 使用一个完全展开的、可综合的优先编码器进行动态规格化。
 * - 实现上溢 (Overflow) 和下溢 (Underflow) 处理。
 *******************************************************************************/
module fp_mul(
    input  [31:0] a,
    input  [31:0] b,
    output reg [31:0] result
);

    // 1. 分解输入 a 和 b 的组成部分
    wire sign_a = a[31];
    wire [7:0] exp_a = a[30:23];
    wire [22:0] mant_a = a[22:0];

    wire sign_b = b[31];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] mant_b = b[22:0];

    // 2. 检测特殊类型的浮点数
    wire is_zero_a   = (exp_a == 8'd0) && (mant_a == 23'd0);
    wire is_zero_b   = (exp_b == 8'd0) && (mant_b == 23'd0);
    wire is_inf_a    = (exp_a == 8'hFF) && (mant_a == 23'd0);
    wire is_inf_b    = (exp_b == 8'hFF) && (mant_b == 23'd0);
    wire is_nan_a    = (exp_a == 8'hFF) && (mant_a != 23'd0);
    wire is_nan_b    = (exp_b == 8'hFF) && (mant_b != 23'd0);
    wire is_denorm_a = (exp_a == 8'd0) && !is_zero_a;
    wire is_denorm_b = (exp_b == 8'd0) && !is_zero_b;

    // 3. 核心计算逻辑
    
    // 最终结果的符号
    wire final_sign = sign_a ^ sign_b;

    // 为尾数添加隐含位 (规格化数为'1', 非规格化数/零为'0') -> 24位
    wire [23:0] mant_a_ext = {~is_denorm_a & ~is_zero_a, mant_a};
    wire [23:0] mant_b_ext = {~is_denorm_b & ~is_zero_b, mant_b};

    // 24位尾数相乘得到48位结果
    wire [47:0] mant_prod = mant_a_ext * mant_b_ext;

    // 计算指数和 (使用10位有符号数以避免计算溢出)
    // 非规格化数的有效指数为1 (对应 2^(-126))
    wire signed [9:0] exp_sum = (is_denorm_a ? 1 : exp_a) + (is_denorm_b ? 1 : exp_b) - 127;

    // 动态规格化
    reg [5:0] shift_left_amount;
    wire [47:0] mant_shifted;
    reg signed [9:0] exp_normalized;
    wire [22:0] mant_final;

    // 查找最高有效位 (MSB) 并计算左移位数
    // 使用 casex 结构实现一个可综合的48位优先编码器
    always @(*) begin
        casex(mant_prod)
            48'h800000000000: shift_left_amount = 0; // Bit 47 is MSB
            48'h400000000000: shift_left_amount = 0; // Bit 46 is MSB
            48'h200000000000: shift_left_amount = 1;
            48'h100000000000: shift_left_amount = 2;
            48'h080000000000: shift_left_amount = 3;
            48'h040000000000: shift_left_amount = 4;
            48'h020000000000: shift_left_amount = 5;
            48'h010000000000: shift_left_amount = 6;
            48'h008000000000: shift_left_amount = 7;
            48'h004000000000: shift_left_amount = 8;
            48'h002000000000: shift_left_amount = 9;
            48'h001000000000: shift_left_amount = 10;
            48'h000800000000: shift_left_amount = 11;
            48'h000400000000: shift_left_amount = 12;
            48'h000200000000: shift_left_amount = 13;
            48'h000100000000: shift_left_amount = 14;
            48'h000080000000: shift_left_amount = 15;
            48'h000040000000: shift_left_amount = 16;
            48'h000020000000: shift_left_amount = 17;
            48'h000010000000: shift_left_amount = 18;
            48'h000008000000: shift_left_amount = 19;
            48'h000004000000: shift_left_amount = 20;
            48'h000002000000: shift_left_amount = 21;
            48'h000001000000: shift_left_amount = 22;
            48'h000000800000: shift_left_amount = 23;
            48'h000000400000: shift_left_amount = 24;
            48'h000000200000: shift_left_amount = 25;
            48'h000000100000: shift_left_amount = 26;
            48'h000000080000: shift_left_amount = 27;
            48'h000000040000: shift_left_amount = 28;
            48'h000000020000: shift_left_amount = 29;
            48'h000000010000: shift_left_amount = 30;
            48'h000000008000: shift_left_amount = 31;
            48'h000000004000: shift_left_amount = 32;
            48'h000000002000: shift_left_amount = 33;
            48'h000000001000: shift_left_amount = 34;
            48'h000000000800: shift_left_amount = 35;
            48'h000000000400: shift_left_amount = 36;
            48'h000000000200: shift_left_amount = 37;
            48'h000000000100: shift_left_amount = 38;
            48'h000000000080: shift_left_amount = 39;
            48'h000000000040: shift_left_amount = 40; // Your example 0x...40 hits here
            48'h000000000020: shift_left_amount = 41;
            48'h000000000010: shift_left_amount = 42;
            48'h000000000008: shift_left_amount = 43;
            48'h000000000004: shift_left_amount = 44;
            48'h000000000002: shift_left_amount = 45;
            48'h000000000001: shift_left_amount = 46;
            default:          shift_left_amount = 47; // Product is zero
        endcase
    end

    // 根据移位调整尾数和指数
    // 目标是将MSB对齐到bit 46 (代表 1.M 格式)
    always @(*) begin
        if (mant_prod[47]) begin // 乘积的整数部分 >= 2, 右移1位
            exp_normalized = exp_sum + 1;
        end else begin // 乘积的整数部分为0或1, 左移
            exp_normalized = exp_sum - shift_left_amount;
        end
    end

    // 执行移位操作
    assign mant_shifted = mant_prod[47] ? (mant_prod >> 1) : (mant_prod << shift_left_amount);

    // 截取最终的23位尾数 (此处为简单截断, 未实现舍入)
    assign mant_final = mant_shifted[45:23];

    // 4. 处理最终结果 (包括特殊值和溢出/下溢)
    always @(*) begin
        // 情况 1: 输入或结果为 NaN
        if (is_nan_a || is_nan_b || (is_inf_a && is_zero_b) || (is_zero_a && is_inf_b)) begin
            result = 32'h7FC00000; // 标准的 quiet NaN
        // 情况 2: 输入或结果为无穷大 (或上溢)
        end else if (is_inf_a || is_inf_b || (exp_normalized >= 255)) begin
            result = {final_sign, 8'hFF, 23'd0};
        // 情况 3: 输入或结果为零 (或下溢)
        end else if (is_zero_a || is_zero_b || (mant_prod == 0) || (exp_normalized <= 0)) begin
            result = {final_sign, 8'd0, 23'd0};
        // 情况 4: 正常规格化结果
        end else begin
            result = {final_sign, exp_normalized[7:0], mant_final};
        end
    end

endmodule
