`timescale 1ns / 1ps

module PE_core_tb;

    // Parameters for PE_core module
    parameter ARRAY_SIZE = 32;
    parameter DATA_WIDTH = 32;       // 32位浮点
    parameter SRAM_DATA_WIDTH = ARRAY_SIZE * DATA_WIDTH; // 16*32=512
    parameter K_ACCUM_DEPTH = 64;    // Reduced for faster simulation
    parameter OUTCOME_WIDTH = 32;    // 输出32位浮点

    // Inputs to PE_core
    reg clk;
    reg srstn;
    reg alu_start;
    reg [8:0] cycle_num;
    reg [SRAM_DATA_WIDTH-1:0] sram_rdata_w; // 一列矩阵 (weights)
    reg [DATA_WIDTH-1:0] sram_rdata_v;       // 单个vector值 (input vector element)

    // Outputs from PE_core
    wire [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] mul_outcome;

    // Loop variables declared at module level for broader compatibility
    integer i;
    integer k;
    integer j;

    // Instantiate the PE_core module
    PE_core #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .K_ACCUM_DEPTH(K_ACCUM_DEPTH),
        .OUTCOME_WIDTH(OUTCOME_WIDTH)
    ) u_pe_core (
        .clk(clk),
        .srstn(srstn),
        .alu_start(alu_start),
        .cycle_num(cycle_num),
        .sram_rdata_w(sram_rdata_w),
        .sram_rdata_v(sram_rdata_v),
        .mul_outcome(mul_outcome)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period, 100MHz clock
    end

    // Test sequence
    initial begin
        // Initialize inputs
        srstn = 0; // Assert reset
        alu_start = 0;
        cycle_num = 0;
        sram_rdata_w = 0;
        sram_rdata_v = 0;

        $display("--------------------------------------------------");
        $display("Starting PE_core Testbench");
        $display("--------------------------------------------------");

        #100; // Wait for some time for reset to settle

        srstn = 1; // Deassert reset
        $display("At %0t: Reset deasserted.", $time);

        // --- Phase 1: Load Weights ---
        // Example weights (represented as 32-bit hex values for floats)
        // Let's use some simple values for testing, e.g., 1.0, 2.0, 3.0, ..., 8.0
        // IEEE 754 single precision:
        // 1.0 -> 3f800000
        // 2.0 -> 40000000
        // 3.0 -> 40400000
        // 4.0 -> 40800000
        // 5.0 -> 40a00000
        // 6.0 -> 40c00000
        // 7.0 -> 40e00000
        // 8.0 -> 41000000
        sram_rdata_w = {
            32'h41000000, // 8.0
            32'h40e00000, // 7.0
            32'h40c00000, // 6.0
            32'h40a00000, // 5.0
            32'h40800000, // 4.0
            32'h40400000, // 3.0
            32'h40000000, // 2.0
            32'h3f800000, // 1.0
            32'h3f000000, // 0.5
            32'h3e800000, // 0.25
            32'h3e000000, // 0.125
            32'h3d800000, // 0.0625
            32'h3d000000, // 0.03125
            32'h3c800000, // 0.015625
            32'h3c000000, // 0.0078125
            32'h3b800000, // 0.00390625
            32'h41000000, // 8.0
            32'h40e00000, // 7.0
            32'h40c00000, // 6.0
            32'h40a00000, // 5.0
            32'h40800000, // 4.0
            32'h40400000, // 3.0
            32'h40000000, // 2.0
            32'h3f800000, // 1.0
            32'h3f000000, // 0.5
            32'h3e800000, // 0.25
            32'h3e000000, // 0.125
            32'h3d800000, // 0.0625
            32'h3d000000, // 0.03125
            32'h3c800000, // 0.015625
            32'h3c000000, // 0.0078125
            32'h3b800000 // 0.00390625
        };

        alu_start = 1; // Indicate start of ALU operation (and weight loading)
        cycle_num = 0; // Initial cycle num, before accumulation starts

        #10; // Wait one clock cycle for weights to load
        $display("At %0t: Weights loaded (sram_rdata_w: %h), alu_start asserted.", $time, sram_rdata_w);
        for (k = 0; k < ARRAY_SIZE; k = k + 1) begin
            $display("    weight_queue[%0d] = %h (%f)", k, sram_rdata_w[k*DATA_WIDTH +: DATA_WIDTH], ieee754_to_real(sram_rdata_w[k*DATA_WIDTH +: DATA_WIDTH]));
        end

        // --- Phase 2: Multiply-Accumulate Cycles ---
        alu_start = 1; // Keep alu_start high for accumulation phase
        for (i = 0; i < K_ACCUM_DEPTH; i = i + 1) begin
            cycle_num = i;
            // Provide a new vector value for each cycle
            // Let's use 0.5, 1.0, 1.5, 2.0, ...
            // 0.5 -> 3f000000
            // 1.0 -> 3f800000
            // 1.5 -> 3fc00000
            // 2.0 -> 40000000
            sram_rdata_v = float_to_ieee754(0.5 + i * 0.5);
            #10; // Wait one clock cycle

            $display("At %0t: Cycle %0d, sram_rdata_v = %h (%f)", $time, cycle_num, sram_rdata_v, ieee754_to_real(sram_rdata_v));
            // Display intermediate or final results based on cycle_num
            if (i == K_ACCUM_DEPTH - 1) begin
                #10; // Wait an extra cycle for the final accumulation to propagate
                $display("At %0t: End of accumulation cycles. Final mul_outcome = %h", $time, mul_outcome);
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    // Extract each 32-bit outcome
                    // mul_outcome is indexed from MSB down to LSB
                    // So, the first element (index 0) of acc_reg is at the MSB end of mul_outcome
                    // (ARRAY_SIZE - 1 - j) maps acc_reg[j] to the correct position
                    // For example, for ARRAY_SIZE=8, j=0 (acc_reg[0]) maps to mul_outcome[255:224] (8-0-1 = 7, 7*32=224)
                    // For example, for ARRAY_SIZE=8, j=7 (acc_reg[7]) maps to mul_outcome[31:0] (8-7-1 = 0, 0*32=0)
                    // The 'mul_outcome_reg[((ARRAY_SIZE-i) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH] = acc_reg[i];' in PE_core
                    // means the last element (acc_reg[ARRAY_SIZE-1]) goes to bits 31:0
                    // and the first element (acc_reg[0]) goes to the highest bits.
                    // So to display acc_reg[j], we need to read from the corresponding segment.
                    // The Verilog `[start_bit -: width]` syntax reads from `start_bit` down to `start_bit - width + 1`.
                    // The `PE_core` output logic does: mul_outcome_reg[((ARRAY_SIZE-i) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH] = acc_reg[i];
                    // This means acc_reg[0] is at bits [ARRAY_SIZE*OUTCOME_WIDTH - 1 : (ARRAY_SIZE-1)*OUTCOME_WIDTH]
                    // acc_reg[1] is at bits [(ARRAY_SIZE-1)*OUTCOME_WIDTH - 1 : (ARRAY_SIZE-2)*OUTCOME_WIDTH]
                    // ...
                    // acc_reg[j] is at bits [(ARRAY_SIZE-j)*OUTCOME_WIDTH - 1 : (ARRAY_SIZE-j-1)*OUTCOME_WIDTH]
                    // The correct indexing for acc_reg[j] from mul_outcome is:
                    // starting bit: (ARRAY_SIZE - 1 - j) * OUTCOME_WIDTH + (OUTCOME_WIDTH - 1)
                    // ending bit: (ARRAY_SIZE - 1 - j) * OUTCOME_WIDTH
                    // Verilog slicing is [MSB:LSB]
                    // So, we need to extract from (ARRAY_SIZE - (j+1)) * OUTCOME_WIDTH and up to (ARRAY_SIZE - j) * OUTCOME_WIDTH - 1
                    // Correct extraction: mul_outcome[((ARRAY_SIZE - j) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH]
                    $display("    Outcome[%0d] = %h (%f)", j, mul_outcome[((ARRAY_SIZE - j) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH],
                             ieee754_to_real(mul_outcome[((ARRAY_SIZE - j) * OUTCOME_WIDTH) - 1 -: OUTCOME_WIDTH]));
                end
            end
        end

        alu_start = 0; // End ALU operation
        #100; // Final delay
        $display("--------------------------------------------------");
        $display("End of PE_core Testbench");
        $display("--------------------------------------------------");
        $finish; // End simulation
    end

    // Function to convert 32-bit IEEE 754 float (represented as bit vector) to real number
    // This is a utility function for the testbench, not synthesizable logic.
    function real ieee754_to_real; // Removed 'automatic'
        input [31:0] f_val;
        begin
            reg sign_bit;
            reg [7:0] exponent_bits;
            reg [22:0] mantissa_bits;
            real sign;
            real exponent;
            real mantissa;
            integer i_loop; // Local loop variable

            sign_bit = f_val[31];
            exponent_bits = f_val[30:23];
            mantissa_bits = f_val[22:0];

            sign = (sign_bit == 1'b1) ? -1.0 : 1.0;

            if (exponent_bits == 8'b0) begin // Denormalized or Zero
                if (mantissa_bits == 23'b0) begin
                    ieee754_to_real = sign * 0.0; // +/- Zero
                end else begin
                    // Denormalized: 2^-126 * (0.fraction)
                    mantissa = 0.0;
                    for (i_loop = 0; i_loop < 23; i_loop = i_loop + 1) begin
                        if (mantissa_bits[i_loop]) begin
                            mantissa = mantissa + (2.0**(-23 + i_loop));
                        end
                    end
                    ieee754_to_real = sign * (2.0**(-126)) * mantissa;
                end
            end else if (exponent_bits == 8'hff) begin // Infinity or NaN
                if (mantissa_bits == 23'b0) begin
                    ieee754_to_real = sign * 1.0e300; // 用极大数近似无穷
                end else begin
                    ieee754_to_real = 0.0; // 用0.0代表NaN
                end
            end else begin // Normalized
                exponent = exponent_bits - 8'd127;
                mantissa = 1.0; // Implicit leading 1
                for (i_loop = 0; i_loop < 23; i_loop = i_loop + 1) begin
                    if (mantissa_bits[i_loop]) begin
                        mantissa = mantissa + (2.0**(-23 + i_loop));
                        end
                    end
                ieee754_to_real = sign * (2.0**(exponent)) * mantissa;
            end
        end
    endfunction

    // Function to convert real number to 32-bit IEEE 754 float (represented as bit vector)
    // This is a utility function for the testbench, not synthesizable logic.
    function [31:0] float_to_ieee754; // Removed 'automatic'
        input real r_val;
        begin
            reg sign_bit;
            reg [7:0] exponent_bits;
            reg [22:0] mantissa_bits;
            real abs_val;
            integer exponent_int;
            real normalized_mantissa;
            integer i_loop; // Local loop variable

            abs_val = (r_val < 0) ? -r_val : r_val;
            sign_bit = (r_val < 0) ? 1'b1 : 1'b0;

            if (abs_val == 0.0) begin
                float_to_ieee754 = 32'h0; // +/- Zero
            end else if (abs_val == 1.0e300) begin
                float_to_ieee754 = (sign_bit == 1'b1) ? 32'hff800000 : 32'h7f800000; // +/- Infinity
            end else if (abs_val == 0.0) begin
                float_to_ieee754 = 32'h7fc00000; // Quiet NaN
            end else begin
                exponent_int = 0;
                normalized_mantissa = abs_val;

                // Normalize the number to 1.xxxx * 2^exponent
                if (abs_val >= 1.0) begin
                    while (normalized_mantissa >= 2.0) begin
                        normalized_mantissa = normalized_mantissa / 2.0;
                        exponent_int = exponent_int + 1;
                    end
                end else begin // abs_val < 1.0
                    exponent_int = -1; // Initial guess for denormalized numbers or very small normalized numbers
                    while (normalized_mantissa < 1.0) begin
                        normalized_mantissa = normalized_mantissa * 2.0;
                        exponent_int = exponent_int - 1;
                    end
                end

                exponent_bits = exponent_int + 127; // Add bias

                // Extract mantissa (fraction part)
                mantissa_bits = 0;
                normalized_mantissa = normalized_mantissa - 1.0; // Remove implicit leading 1
                for (i_loop = 22; i_loop >= 0; i_loop = i_loop - 1) begin
                    if (normalized_mantissa >= (2.0**i_loop)) begin
                        mantissa_bits[i_loop] = 1'b1;
                        normalized_mantissa = normalized_mantissa - (2.0**i_loop);
                    end
                end

                float_to_ieee754 = {sign_bit, exponent_bits, mantissa_bits};
            end
        end
    endfunction

endmodule
