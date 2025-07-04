// PE_core module refactored to use a dedicated fp_mac (Multiply-Accumulate) unit.
// This improves modularity by encapsulating the multiply and add operations.
module PE_core#(
    parameter ARRAY_SIZE = 32,
    parameter SRAM_DATA_WIDTH = 1024, // 32*32=1024
    parameter DATA_WIDTH = 32,       // 32-bit floating point
    parameter K_ACCUM_DEPTH = 64,    // Accumulation depth
    parameter OUTCOME_WIDTH = 32     // Output 32-bit floating point
)
(
    input clk,
    input srstn,
    input alu_start,
    input [8:0] cycle_num,
    input [SRAM_DATA_WIDTH-1:0] sram_rdata_w, // A column of the matrix
    input [DATA_WIDTH-1:0] sram_rdata_v,      // A single vector value
    output [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome
);

// Internal registers
reg [DATA_WIDTH-1:0] weight_queue [0:ARRAY_SIZE-1];
reg [OUTCOME_WIDTH-1:0] acc_reg [0:ARRAY_SIZE-1];

// Loop variable
integer i;

// Weight queue loading logic
always @(posedge clk) begin
    if (~srstn) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            weight_queue[i] <= 32'b0;
        end
    end else if (alu_start) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            // Load a slice of the wide SRAM data into each weight queue element
            weight_queue[i] <= sram_rdata_w[i*DATA_WIDTH +: DATA_WIDTH];
        end
    end
end

// *** MODIFICATION START ***
// The separate mul_result and add_result wires are replaced by a single mac_result wire.
wire [OUTCOME_WIDTH-1:0] mac_result [0:ARRAY_SIZE-1];

genvar gi;
generate
    // Instantiate the new fp_mac unit for each element in the array.
    // This replaces the separate fp_mul and fp_add instantiations.
    for (gi = 0; gi < ARRAY_SIZE; gi = gi + 1) begin: MAC_PIPE
        fp_mac u_fp_mac (
            .a(weight_queue[gi]), // Multiplicand 1
            .b(sram_rdata_v),     // Multiplicand 2
            .c(acc_reg[gi]),      // Value to add (from accumulator)
            .result(mac_result[gi]) // Output of the MAC operation
        );
    end
endgenerate

// Accumulator register logic
always @(posedge clk) begin
    if(~srstn) begin
        for(i=0; i<ARRAY_SIZE; i=i+1) begin
            acc_reg[i] <= 32'b0;
        end
    // The accumulation now uses the result from the fp_mac unit
    end else if(alu_start & cycle_num < K_ACCUM_DEPTH - 1) begin
        for(i=0; i<ARRAY_SIZE; i=i+1) begin
            acc_reg[i] <= mac_result[i];
        end
    end
end
// *** MODIFICATION END ***


// Combinational logic to assign accumulator values to the output port
reg [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome_reg;
always @(*) begin
    for(i=0; i<ARRAY_SIZE; i=i+1) begin
        // This maps acc_reg[i] to the corresponding slice of the output vector.
        // The indexing reverses the order, so mul_outcome = {acc_reg[0], acc_reg[1], ...}
        mul_outcome_reg[((ARRAY_SIZE-i) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH] = acc_reg[i];
    end
end
assign mul_outcome = mul_outcome_reg;

endmodule


// *** NEW MODULE ***
// Floating-Point Multiply-Accumulate (MAC) Unit
// This module wraps the fp_mul and fp_add modules into a single unit.
// It performs the operation: result = (a * b) + c
module fp_mac (
    input  [31:0] a,
    input  [31:0] b,
    input  [31:0] c,
    output [31:0] result
);

    // Internal wire for the multiplication result
    wire [31:0] mul_result;

    // Instantiate the multiplier
    fp_mul u_fp_mul (
        .a(a),
        .b(b),
        .result(mul_result)
    );

    // Instantiate the adder
    // It adds the multiplication result to the input 'c'
    fp_add u_fp_add (
        .a(mul_result),
        .b(c),
        .out(result)
    );

endmodule


// Floating-Point Multiplier (IEEE 754)
// This module is unchanged, but is now instantiated by fp_mac.
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
    // Add implicit leading '1' for normalized numbers
    assign mant_a = (exp_a == 0) ? {1'b0, a[22:0]} : {1'b1, a[22:0]};
    assign mant_b = (exp_b == 0) ? {1'b0, b[22:0]} : {1'b1, b[22:0]};
    assign mant_mul = mant_a * mant_b;

    assign exp_sum = exp_a + exp_b - 8'd127;
    assign zero = (exp_a == 0 && a[22:0] == 0) || (exp_b == 0 && b[22:0] == 0);

    // Adjust exponent and mantissa based on multiplication result
    assign exp_res = zero ? 8'd0 : (mant_mul[47] ? exp_sum + 1 : exp_sum);
    assign mant_res = zero ? 23'd0 : (mant_mul[47] ? mant_mul[46:24] : mant_mul[45:23]);

    assign result = {sign, exp_res, mant_res};
endmodule


// Floating-Point Adder (IEEE 754)
// This module is unchanged, but is now instantiated by fp_mac.
module fp_add(a, b, out);
  input [31:0] a, b;
  output [31:0] out;   

  // Note: Redundant 'wire [31:0] out' declaration removed for cleanliness.
  
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

  // Instantiation of the normalizer for post-addition normalization
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
    i_e = 0;
    i_m = 0;
    // Step 1: Deconstruct inputs into sign, exponent, and mantissa
    a_sign = a[31];
    if(a[30:23] == 0) begin // Denormalized or zero
        a_exponent = 8'b00000000;
        a_mantissa = {1'b0, a[22:0]};
    end else begin // Normalized
        a_exponent = a[30:23];
        a_mantissa = {1'b1, a[22:0]}; // Add implicit '1'
    end

    b_sign = b[31];
    if(b[30:23] == 0) begin // Denormalized or zero
        b_exponent = 8'b00000000;
        b_mantissa = {1'b0, b[22:0]};
    end else begin // Normalized
        b_exponent = b[30:23];
        b_mantissa = {1'b1, b[22:0]}; // Add implicit '1'
    end

    // Step 2: Handle special cases (Zero, NaN, Infinity)
    if ((a_exponent == 8'd0 && a_mantissa == 24'd0) && (b_exponent == 8'd0 && b_mantissa == 24'd0)) begin
        o_sign = 1'b0;
        o_exponent = 8'd0;
        o_mantissa = 25'd0;
    end
    else if ((a_exponent == 8'd255 && a_mantissa != 24'd0) || (b_exponent == 8'd0 && b_mantissa == 24'd0)) begin // a is NaN or b is 0, return a
        o_sign = a_sign;
        o_exponent = a_exponent;
        o_mantissa = {1'b0, a_mantissa};
    end
    else if ((b_exponent == 8'd255 && b_mantissa != 24'd0) || (a_exponent == 8'd0 && a_mantissa == 24'd0)) begin // b is NaN or a is 0, return b
        o_sign = b_sign;
        o_exponent = b_exponent;
        o_mantissa = {1'b0, b_mantissa};
    end
    else if ((a_exponent == 8'd255) || (b_exponent == 8'd255)) begin // a or b is infinity
        o_sign = a_sign ^ b_sign;
        o_exponent = 8'd255;
        o_mantissa = 25'd0;
    end
    else begin // Step 3: Normal addition/subtraction
        if (a_exponent == b_exponent) begin // Case 1: Exponents are equal
            o_exponent = a_exponent;
            if (a_sign == b_sign) begin // Signs are same: Add
                o_mantissa = a_mantissa + b_mantissa;
                o_mantissa[24] = 1; // This seems incorrect, should be based on carry-out
                o_sign = a_sign;
            end else begin // Signs are different: Subtract
                if(a_mantissa >= b_mantissa) begin
                    o_mantissa = a_mantissa - b_mantissa;
                    o_sign = a_sign;
                end else begin
                    o_mantissa = b_mantissa - a_mantissa;
                    o_sign = b_sign;
                end
            end
        end else begin // Case 2: Exponents are different
            // Align mantissas by shifting the smaller number
            if (a_exponent > b_exponent) begin
                o_exponent = a_exponent;
                o_sign = a_sign;
                diff = a_exponent - b_exponent;
                tmp_mantissa = b_mantissa >> diff;
                if (a_sign == b_sign)
                    o_mantissa = a_mantissa + tmp_mantissa;
                else
                    o_mantissa = a_mantissa - tmp_mantissa;
            end else begin // b_exponent > a_exponent
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
        // Step 4: Normalize the result
        if(o_mantissa[24] == 1) begin // Overflow after addition
            o_exponent = o_exponent + 1;
            o_mantissa = o_mantissa >> 1;
        end else if((o_mantissa[23] != 1) && (o_exponent != 0)) begin // Result needs left shifting
            i_e = o_exponent;
            i_m = o_mantissa;
            o_exponent = o_e;
            o_mantissa = o_m;
        end
    end
  end
endmodule 

// Normalizer for the adder
// This is a large priority encoder to find the leading one and shift left.
module addition_normaliser(in_e, in_m, out_e, out_m);
  input [7:0] in_e;
  input [24:0] in_m;
  output reg [7:0] out_e;
  output reg [24:0] out_m;
 
  // Note: Redundant wire declarations removed for cleanliness.
  
  always @ ( * ) begin
    // This structure implements a priority encoder to find the most significant bit
    // and shift the mantissa left accordingly, adjusting the exponent.
    if      (in_m[23:22] == 2'b01) begin out_e = in_e - 1;  out_m = in_m << 1;  end
    else if (in_m[23:21] == 3'b001) begin out_e = in_e - 2;  out_m = in_m << 2;  end
    else if (in_m[23:20] == 4'b0001) begin out_e = in_e - 3;  out_m = in_m << 3;  end
    else if (in_m[23:19] == 5'b00001) begin out_e = in_e - 4;  out_m = in_m << 4;  end
    else if (in_m[23:18] == 6'b000001) begin out_e = in_e - 5;  out_m = in_m << 5;  end
    else if (in_m[23:17] == 7'b0000001) begin out_e = in_e - 6;  out_m = in_m << 6;  end
    else if (in_m[23:16] == 8'b00000001) begin out_e = in_e - 7;  out_m = in_m << 7;  end
    else if (in_m[23:15] == 9'b000000001) begin out_e = in_e - 8;  out_m = in_m << 8;  end
    else if (in_m[23:14] == 10'b0000000001) begin out_e = in_e - 9;  out_m = in_m << 9;  end
    else if (in_m[23:13] == 11'b00000000001) begin out_e = in_e - 10; out_m = in_m << 10; end
    else if (in_m[23:12] == 12'b000000000001) begin out_e = in_e - 11; out_m = in_m << 11; end
    else if (in_m[23:11] == 13'b0000000000001) begin out_e = in_e - 12; out_m = in_m << 12; end
    else if (in_m[23:10] == 14'b00000000000001) begin out_e = in_e - 13; out_m = in_m << 13; end
    else if (in_m[23:9]  == 15'b000000000000001) begin out_e = in_e - 14; out_m = in_m << 14; end
    else if (in_m[23:8]  == 16'b0000000000000001) begin out_e = in_e - 15; out_m = in_m << 15; end
    else if (in_m[23:7]  == 17'b00000000000000001) begin out_e = in_e - 16; out_m = in_m << 16; end
    else if (in_m[23:6]  == 18'b000000000000000001) begin out_e = in_e - 17; out_m = in_m << 17; end
    else if (in_m[23:5]  == 19'b0000000000000000001) begin out_e = in_e - 18; out_m = in_m << 18; end
    else if (in_m[23:4]  == 20'b00000000000000000001) begin out_e = in_e - 19; out_m = in_m << 19; end
    else if (in_m[23:3]  == 21'b000000000000000000001) begin out_e = in_e - 20; out_m = in_m << 20; end
    else begin out_e = in_e; out_m = in_m; end // Default case
  end
endmodule
