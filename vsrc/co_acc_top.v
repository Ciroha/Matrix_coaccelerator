//****************************************************************************
// Description:
// Top-level module with corrected logic for writing results to an SRAM.
//****************************************************************************
module top #(
    parameter ARRAY_SIZE      = 32,
    parameter SRAM_DATA_WIDTH = 1024,         // 32*32=1024
    parameter DATA_WIDTH      = 32,           // 32-bit floating point
    parameter K_ACCUM_DEPTH   = 64,           // Accumulation depth for MAC operations
    parameter OUTCOME_WIDTH   = 32,           // Output 32-bit floating point
    parameter SRAM_W_DEPTH    = K_ACCUM_DEPTH,// Depth of the weight SRAM
    parameter SRAM_V_DEPTH    = K_ACCUM_DEPTH, // Depth of the vector SRAM
    // Added a parameter for the depth of the outcome SRAM for clarity
    parameter SRAM_O_DEPTH    = 32
)
(
    input  clk,
    input  srstn,
    input  start_processing, // Top-level start signal
    output processing_done
);

    // Internal signals for controlling the PE core
    reg         alu_start_reg;
    reg  [8:0]  cycle_num_reg;

    // Wires to connect SRAMs to the PE core
    wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w_wire;
    wire [DATA_WIDTH-1:0]      sram_rdata_v_wire;
    wire [(ARRAY_SIZE * OUTCOME_WIDTH) - 1:0] final_result_wire;

    // Address registers for input SRAMs
    reg [$clog2(SRAM_W_DEPTH)-1:0] sram_w_addr;
    reg [$clog2(SRAM_V_DEPTH)-1:0] sram_v_addr;

    // *** MODIFICATION START ***
    // Control signals for the outcome SRAM
    reg outcome_we; // Write enable signal (1 for write, 0 for no-write)
    reg [$clog2(SRAM_O_DEPTH)-1:0] outcome_waddr; // Write address for the outcome SRAM
    // *** MODIFICATION END ***


    //========================================================================
    // INSTANTIATION OF SUB-MODULES
    //========================================================================
    // NOTE: Assuming the use of the 'sram' module created earlier.

    // Instantiate the weight SRAM (for Matrix A)
    sram #(
        .DATA_WIDTH(SRAM_DATA_WIDTH),
        .ADDR_WIDTH($clog2(SRAM_W_DEPTH))
    ) sram_w_inst (
        .clk(clk),
        .csb(1'b0), // Chip select is always active for simplicity
        .wsb(1'b1), // Write disabled (read-only)
        .wdata(0),
        .waddr(0),
        .raddr(sram_w_addr),
        .rdata(sram_rdata_w_wire)
    );

    // Instantiate the vector SRAM (for Vector B)
    sram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH($clog2(SRAM_V_DEPTH))
    ) sram_v_inst (
        .clk(clk),
        .csb(1'b0),
        .wsb(1'b1), // Write disabled (read-only)
        .wdata(0),
        .waddr(0),
        .raddr(sram_v_addr),
        .rdata(sram_rdata_v_wire)
    );

    // Instantiate the outcome SRAM to store the final result
    sram #(
        .DATA_WIDTH(OUTCOME_WIDTH * ARRAY_SIZE),
        .ADDR_WIDTH($clog2(SRAM_O_DEPTH))
    ) sram_outcome_inst (
        .clk(clk),
        .csb(~outcome_we),      // Chip is selected only when writing
        .wsb(~outcome_we),      // Write is enabled only when outcome_we is high
        .wdata(final_result_wire),   // Data to write is the final result from PE core
        .waddr(outcome_waddr),  // Address is controlled by our new logic
        .raddr(0),              // Read port not used in this design
        .rdata()                // Read port not connected
    );

    // Instantiate the PE core
    (* DONT_TOUCH = "true" *)
    PE_core #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .K_ACCUM_DEPTH(K_ACCUM_DEPTH),
        .OUTCOME_WIDTH(OUTCOME_WIDTH)
    ) PE_core_inst (
        .clk(clk),
        .srstn(srstn),
        .alu_start(alu_start_reg),
        .cycle_num(cycle_num_reg),
        .sram_rdata_w(sram_rdata_w_wire),
        .sram_rdata_v(sram_rdata_v_wire),
        .mul_outcome(final_result_wire)
    );

    //========================================================================
    // CONTROL LOGIC
    //========================================================================

    // The processing is considered done for one cycle when the accumulation depth is reached.
    assign processing_done = (cycle_num_reg == K_ACCUM_DEPTH);

    // Main control logic for processing cycles and SRAM write operations
    always @(posedge clk or negedge srstn) begin
        if (!srstn) begin
            // Reset all state registers
            cycle_num_reg <= 0;
            alu_start_reg <= 0;
            sram_w_addr   <= 0;
            sram_v_addr   <= 0;
            outcome_we    <= 1'b0; // Disable writing on reset
            outcome_waddr <= 0;
        end else begin
            // Default: disable writing to outcome SRAM
            outcome_we <= 1'b0;

            if (start_processing && cycle_num_reg == 0) begin
                // Start a new processing job
                alu_start_reg <= 1;
                cycle_num_reg <= cycle_num_reg + 1;
                sram_w_addr   <= sram_w_addr + 1;
                sram_v_addr   <= sram_v_addr + 1;
            end else if (alu_start_reg) begin
                if (processing_done) begin
                    // Processing is finished, stop the PE core for the next cycle.
                    alu_start_reg <= 0;
                    // Enable writing to the outcome SRAM for this single cycle.
                    outcome_we <= 1'b1;
                    // Increment the outcome SRAM address for the next result.
                    outcome_waddr <= outcome_waddr + 1;
                    // Reset cycle counter for the next potential operation
                    cycle_num_reg <= 0;
                end else begin
                    // Continue the accumulation process
                    cycle_num_reg <= cycle_num_reg + 1;
                    sram_w_addr   <= sram_w_addr + 1;
                    sram_v_addr   <= sram_v_addr + 1;
                end
            end
        end
    end

endmodule
