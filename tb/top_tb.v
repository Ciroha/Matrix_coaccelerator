`timescale 1ns / 1ps

//****************************************************************************
// Description:
// Testbench for the 'top' module.
// This testbench initializes the design, starts the processing, and waits
// for the completion signal.
//****************************************************************************
module tb_top;

    // Parameters for the testbench, matching the DUT
    parameter CLK_PERIOD = 10; // Clock period in ns

    // Testbench signals
    reg  clk;
    reg  srstn;
    reg  start_processing;
    wire processing_done;

    // Instantiate the Device Under Test (DUT)
    mac_top uut (
        .clk(clk),
        .srstn(srstn),
        .start_processing(start_processing),
        .processing_done(processing_done)
    );

    // 1. Clock Generation
    // Generate a clock with a period defined by CLK_PERIOD.
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 2. Test Sequence
    // This block controls the simulation flow.
    initial begin
        $display("==================================================");
        $display("Testbench Started at time %t", $time);
        $display("==================================================");

        // --- Reset Phase ---
        // Initialize all inputs and apply active-low reset.
        start_processing = 1'b0;
        srstn = 1'b0; // Assert reset
        $display("[%t] System is in reset.", $time);
        repeat(5) @(posedge clk); // Hold reset for 5 clock cycles

        srstn = 1'b1; // De-assert reset
        $display("[%t] System reset released.", $time);
        @(posedge clk);

        // --- Start Processing Phase ---
        // Wait for a moment before starting the process.
        $display("[%t] Waiting before starting processing...", $time);
        repeat(2) @(posedge clk);

        // Send a single-cycle pulse to start the processing.
        $display("[%t] Pulsing 'start_processing' high for one cycle.", $time);
        start_processing = 1'b1;
        @(posedge clk);
        start_processing = 1'b0;
        
        // --- Wait for Completion Phase ---
        $display("[%t] Processing started. Waiting for 'processing_done' signal...", $time);
        
        // Use a timeout to prevent the simulation from running forever
        // if 'processing_done' never goes high.
        fork
            begin
                // Wait for the 'processing_done' signal to go high.
                wait (processing_done == 1'b1);
                $display("--------------------------------------------------");
                $display("[%t] SUCCESS: 'processing_done' signal received!", $time);
                $display("--------------------------------------------------");
            end
            begin
                // Timeout logic: K_ACCUM_DEPTH is 64, so it should take roughly that many cycles.
                // We'll wait for a bit longer, e.g., 100 cycles.
                #(CLK_PERIOD * 100); 
                $display("--------------------------------------------------");
                $error("[%t] TIMEOUT: 'processing_done' signal was not received.", $time);
                $display("--------------------------------------------------");
                $finish;
            end
        join

        // --- Finish Simulation ---
        $display("[%t] Test sequence complete. Finishing simulation.", $time);
        repeat(5) @(posedge clk);
        $finish;
    end

    // Optional: Dump waves for debugging
    // initial begin
    //     $dumpfile("tb_top.vcd");
    //     $dumpvars(0, tb_top);
    // end

endmodule
