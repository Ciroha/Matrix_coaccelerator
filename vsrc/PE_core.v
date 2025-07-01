module PE_core#(
    parameter ARRAY_SIZE = 16,
    parameter SRAM_DATA_WIDTH = 512, // 16*32=512
    parameter DATA_WIDTH = 32,      // 32位浮点
    parameter K_ACCUM_DEPTH = 32,   // 累加深度
    parameter DATA_SET = 1,         // 数据集个数
    parameter OUTCOME_WIDTH = 32    // 输出32位浮点
)
(
    input clk,
    input srstn,
    input alu_start,
    input [8:0] cycle_num,
    input [SRAM_DATA_WIDTH-1:0] sram_rdata_w, // 一列矩阵
    input [DATA_WIDTH-1:0] sram_rdata_v,      // 单个vector值
    output [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome
);

// 浮点数据队列
reg [DATA_WIDTH-1:0] weight_queue [0:ARRAY_SIZE-1];
reg [OUTCOME_WIDTH-1:0] acc_reg [0:ARRAY_SIZE-1];

integer i;

// 权重队列初始化与加载
always @(posedge clk) begin
    if (~srstn) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] <= 32'b0;
        end
    end else if (alu_start) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] <= sram_rdata_w[i*DATA_WIDTH +: DATA_WIDTH];
        end
    end
end

// 浮点累加器
wire [31:0] mul_result [0:ARRAY_SIZE-1];
wire [31:0] add_result [0:ARRAY_SIZE-1];

genvar gi;
generate
    for (gi = 0; gi < ARRAY_SIZE; gi = gi + 1) begin: FP_PIPE
        fp_mul u_fp_mul(
            .a(weight_queue[gi]),
            .b(sram_rdata_v),
            .result(mul_result[gi])
        );
        fp_add u_fp_add(
            .a(acc_reg[gi]),
            .b(mul_result[gi]),
            .out(add_result[gi])
        );
    end
endgenerate

always @(posedge clk) begin
    if(~srstn) begin
        for(i=0; i<ARRAY_SIZE; i=i+1) begin
            acc_reg[i] <= 32'b0;
        end
    end else if(alu_start & cycle_num < K_ACCUM_DEPTH - 1) begin
        for(i=0; i<ARRAY_SIZE; i=i+1) begin
            acc_reg[i] <= add_result[i];
        end
    end
end

// 输出拼接
reg [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome_reg;
always @(*) begin
    for(i=0; i<ARRAY_SIZE; i=i+1) begin
        mul_outcome_reg[((ARRAY_SIZE-i) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH] = acc_reg[i];
    end
end
assign mul_outcome = mul_outcome_reg;

endmodule

// 需要提供fp_mul和fp_add模块（32位浮点IEEE 754）
module fp_mul(
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] result
);
    wire sign;
    wire [7:0] exp_a, exp_b, exp_sum;
    wire [23:0] mant_a, mant_b;
    wire [47:0] mant_mul;
    wire [7:0] exp_res;
    wire [22:0] mant_res;
    wire zero;

    assign sign = a[31] ^ b[31];
    assign exp_a = a[30:23];
    assign exp_b = b[30:23];
    assign mant_a = (exp_a == 0) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    assign mant_b = (exp_b == 0) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    assign mant_mul = mant_a * mant_b;

    assign exp_sum = exp_a + exp_b - 8'd127;
    assign zero = (exp_a == 0 && a[22:0] == 0) || (exp_b == 0 && b[22:0] == 0);

    assign exp_res = zero ? 8'd0 : (mant_mul[47] ? exp_sum + 1 : exp_sum);
    assign mant_res = zero ? 23'd0 : (mant_mul[47] ? mant_mul[46:24] : mant_mul[45:23]);

    assign result = {sign, exp_res, mant_res};
endmodule


module fp_add(a, b, out);
  input [31:0] a, b;
  output [31:0] out;   

  wire [31:0] out;
  
  reg a_sign;
  reg b_sign;
  reg [7:0] a_exponent;
  reg [7:0] b_exponent;
  reg [23:0] a_mantissa;
  reg [23:0] b_mantissa;   
  
  reg o_sign;
  reg [7:0] o_exponent;
  reg [24:0] o_mantissa; 

  reg [7:0] diff;
  reg [23:0] tmp_mantissa;

  reg [7:0] i_e;
  reg [24:0] i_m;
  wire [7:0] o_e;
  wire [24:0] o_m;

  addition_normaliser norm1(
    .in_e(i_e),
    .in_m(i_m),
    .out_e(o_e),
    .out_m(o_m)
  );

  assign out[31] = o_sign;
  assign out[30:23] = o_exponent;
  assign out[22:0] = o_mantissa[22:0];

  always @ (*) begin
    // 先解析输入
    a_sign = a[31];
    if(a[30:23] == 0) begin
        a_exponent = 8'b00000000;
        a_mantissa = {1'b0, a[22:0]};
    end else begin
        a_exponent = a[30:23];
        a_mantissa = {1'b1, a[22:0]};
    end

    b_sign = b[31];
    if(b[30:23] == 0) begin
        b_exponent = 8'b00000000;
        b_mantissa = {1'b0, b[22:0]};
    end else begin
        b_exponent = b[30:23];
        b_mantissa = {1'b1, b[22:0]};
    end

    // 特殊情况：全零输入
    if ((a_exponent == 8'd0 && a_mantissa == 24'd0) && (b_exponent == 8'd0 && b_mantissa == 24'd0)) begin
        o_sign = 1'b0;
        o_exponent = 8'd0;
        o_mantissa = 25'd0;
    end
    // a为NaN或b为0，返回a
    else if ((a_exponent == 8'd255 && a_mantissa != 24'd0) || (b_exponent == 8'd0 && b_mantissa == 24'd0)) begin
        o_sign = a_sign;
        o_exponent = a_exponent;
        o_mantissa = {1'b0, a_mantissa};
    end
    // b为NaN或a为0，返回b
    else if ((b_exponent == 8'd255 && b_mantissa != 24'd0) || (a_exponent == 8'd0 && a_mantissa == 24'd0)) begin
        o_sign = b_sign;
        o_exponent = b_exponent;
        o_mantissa = {1'b0, b_mantissa};
    end
    // a或b为无穷，返回无穷
    else if ((a_exponent == 8'd255) || (b_exponent == 8'd255)) begin
        o_sign = a_sign ^ b_sign;
        o_exponent = 8'd255;
        o_mantissa = 25'd0;
    end
    else begin // 正常加法流程
        if (a_exponent == b_exponent) begin // Equal exponents
            o_exponent = a_exponent;
            if (a_sign == b_sign) begin // Equal signs = add
                o_mantissa = a_mantissa + b_mantissa;
                o_mantissa[24] = 1;
                o_sign = a_sign;
            end else begin // Opposite signs = subtract
                if(a_mantissa > b_mantissa) begin
                    o_mantissa = a_mantissa - b_mantissa;
                    o_sign = a_sign;
                end else begin
                    o_mantissa = b_mantissa - a_mantissa;
                    o_sign = b_sign;
                end
            end
        end else begin // Unequal exponents
            if (a_exponent > b_exponent) begin // A is bigger
                o_exponent = a_exponent;
                o_sign = a_sign;
                diff = a_exponent - b_exponent;
                tmp_mantissa = b_mantissa >> diff;
                if (a_sign == b_sign)
                    o_mantissa = a_mantissa + tmp_mantissa;
                else
                    o_mantissa = a_mantissa - tmp_mantissa;
            end else if (a_exponent < b_exponent) begin // B is bigger
                o_exponent = b_exponent;
                o_sign = b_sign;
                diff = b_exponent - a_exponent;
                tmp_mantissa = a_mantissa >> diff;
                if (a_sign == b_sign)
                    o_mantissa = b_mantissa + tmp_mantissa;
                else
                    o_mantissa = b_mantissa - tmp_mantissa;
            end
        end
        // 规格化
        if(o_mantissa[24] == 1) begin
            o_exponent = o_exponent + 1;
            o_mantissa = o_mantissa >> 1;
        end else if((o_mantissa[23] != 1) && (o_exponent != 0)) begin
            i_e = o_exponent;
            i_m = o_mantissa;
            o_exponent = o_e;
            o_mantissa = o_m;
        end
    end
  end
endmodule 

module addition_normaliser(in_e, in_m, out_e, out_m);
  input [7:0] in_e;
  input [24:0] in_m;
  output [7:0] out_e;
  output [24:0] out_m;
  
  wire [7:0] in_e;
  wire [24:0] in_m;
  reg [7:0] out_e;
  reg [24:0] out_m;
  
  
  always @ ( * ) begin
    if (in_m[23:3] == 21'b000000000000000000001) begin
	  out_e = in_e - 20;
	  out_m = in_m << 20;
	end else if (in_m[23:4] == 20'b00000000000000000001) begin
	  out_e = in_e - 19;
	  out_m = in_m << 19;
	end else if (in_m[23:5] == 19'b0000000000000000001) begin
	  out_e = in_e - 18;
	  out_m = in_m << 18;
	end else if (in_m[23:6] == 18'b000000000000000001) begin
	  out_e = in_e - 17;
	  out_m = in_m << 17;
	end else if (in_m[23:7] == 17'b00000000000000001) begin
	  out_e = in_e - 16;
	  out_m = in_m << 16;
	end else if (in_m[23:8] == 16'b0000000000000001) begin
	  out_e = in_e - 15;
	  out_m = in_m << 15;
	end else if (in_m[23:9] == 15'b000000000000001) begin
	  out_e = in_e - 14;
	  out_m = in_m << 14;
	end else if (in_m[23:10] == 14'b00000000000001) begin
	  out_e = in_e - 13;
	  out_m = in_m << 13;
	end else if (in_m[23:11] == 13'b0000000000001) begin
	  out_e = in_e - 12;
	  out_m = in_m << 12;
	end else if (in_m[23:12] == 12'b000000000001) begin
	  out_e = in_e - 11;
	  out_m = in_m << 11;
	end else if (in_m[23:13] == 11'b00000000001) begin
	  out_e = in_e - 10;
      out_m = in_m << 10;
	end else if (in_m[23:14] == 10'b0000000001) begin
	  out_e = in_e - 9;
	  out_m = in_m << 9;
	end else if (in_m[23:15] == 9'b000000001) begin
	  out_e = in_e - 8;
	  out_m = in_m << 8;
	end else if (in_m[23:16] == 8'b00000001) begin
	  out_e = in_e - 7;
	  out_m = in_m << 7;
	end else if (in_m[23:17] == 7'b0000001) begin
	  out_e = in_e - 6;
      out_m = in_m << 6;
	end else if (in_m[23:18] == 6'b000001) begin
	  out_e = in_e - 5;
	  out_m = in_m << 5;
	end else if (in_m[23:19] == 5'b00001) begin
	  out_e = in_e - 4;
	  out_m = in_m << 4;
	end else if (in_m[23:20] == 4'b0001) begin
	  out_e = in_e - 3;
	  out_m = in_m << 3;
	end else if (in_m[23:21] == 3'b001) begin
	  out_e = in_e - 2;
	  out_m = in_m << 2;
	end else if (in_m[23:22] == 2'b01) begin
	  out_e = in_e - 1;
	  out_m = in_m << 1;
	end
  end
endmodule
  