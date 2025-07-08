`timescale 1ns / 1ps

//****************************************************************************
// Testbench for the complete Co_Processor
//****************************************************************************
module tb_Co_Processor;

    //========================================================================
    //==                      Testbench Parameters                        ==
    //========================================================================
    localparam CLK_PERIOD = 10; // Clock period: 10ns -> 100MHz

    // AXI Address Map (mirrored from DUT)
    localparam REG_CTRL_ADDR      = 16'h0000;
    localparam REG_STATUS_ADDR    = 16'h0004;
    localparam REG_VI_BASE_ADDR   = 16'h0010;
    localparam REG_MI_BASE_ADDR   = 16'h0014;
    localparam REG_VO_BASE_ADDR   = 16'h0018;
    localparam REG_ROWS_ADDR      = 16'h0020;
    localparam REG_COLS_ADDR      = 16'h0024;

    // CSR Bit Fields (mirrored from DUT)
    localparam CSR_CTRL_START_BIT = 0;
    localparam CSR_STATUS_DONE_BIT = 1;

    //========================================================================
    //==                         Signal Declarations                        ==
    //========================================================================
    // DUT Connections
    reg         clk;
    reg         rst_n;

    // AXI Master signals (driven by testbench)
    reg  [4:0]  s_awid;
    reg  [31:0] s_awaddr;
    reg         s_awvalid;
    wire        s_awready;
    reg  [31:0] s_wdata;
    reg         s_wvalid;
    wire        s_wready;
    wire [4:0]  s_bid;
    wire [1:0]  s_bresp;
    wire        s_bvalid;
    reg         s_bready;
    reg  [4:0]  s_arid;
    reg  [31:0] s_araddr;
    reg         s_arvalid;
    wire        s_arready;
    wire [4:0]  s_rid;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rlast;
    wire        s_rvalid;
    reg         s_rready;

    // DMA signals
    wire        dma_start;
    wire [31:0] dma_addr;
    wire [31:0] dma_len;
    wire        dma_dir;
    reg         dma_done;
    reg         dma_error;

    //========================================================================
    //==                      DUT Instantiation                             ==
    //========================================================================
    Co_Processor dut (
        .clk(clk),
        .rst_n(rst_n),

        // DMA Interface
        .dma_start(dma_start),
        .dma_addr(dma_addr),
        .dma_len(dma_len),
        .dma_dir(dma_dir),
        .dma_done(dma_done),
        .dma_error(dma_error),

        // AXI4-Lite Slave Bus
        .s_awid(s_awid),
        .s_awaddr(s_awaddr),
        .s_awlen(8'd0), // Unused in AXI-Lite
        .s_awsize(3'd2), // 32-bit
        .s_awburst(2'b01), // INCR
        .s_awlock(1'b0),
        .s_awcache(4'd0),
        .s_awprot(3'd0),
        .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata(s_wdata),
        .s_wstrb(4'b1111), // Write all 4 bytes
        .s_wlast(1'b1), // AXI-Lite always has wlast=1
        .s_wvalid(s_wvalid),
        .s_wready(s_wready),
        .s_bid(s_bid),
        .s_bresp(s_bresp),
        .s_bvalid(s_bvalid),
        .s_bready(s_bready),
        .s_arid(s_arid),
        .s_araddr(s_araddr),
        .s_arlen(8'd0),
        .s_arsize(3'd2),
        .s_arburst(2'b01),
        .s_arlock(1'b0),
        .s_arcache(4'd0),
        .s_arprot(3'd0),
        .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid(s_rid),
        .s_rdata(s_rdata),
        .s_rresp(s_rresp),
        .s_rlast(s_rlast),
        .s_rvalid(s_rvalid),
        .s_rready(s_rready)
    );

    //========================================================================
    //==                      Clock and Reset Generation                    ==
    //========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        $display("======================================================");
        $display("== Starting Co-Processor Testbench                  ==");
        $display("======================================================");
        rst_n = 1'b0; // Assert reset
        # (CLK_PERIOD * 5);
        rst_n = 1'b1; // De-assert reset
        $display("[%0t] System reset released.", $time);
    end

    //========================================================================
    //==                      AXI Master Tasks                            ==
    //========================================================================
// Task to perform an AXI write with corrected handshake
task axi_write(input [31:0] addr, input [31:0] data);
    begin
        // ==========================================================
        // == Phase 1: Address Handshake                           ==
        // ==========================================================
        @(posedge clk);
        s_awaddr <= addr;
        s_awvalid <= 1'b1;
        $display("[%0t] AXI Write: Asserting address. Addr=0x%h", $time, addr);

        // Wait ONLY for the address to be accepted
        wait (s_awready);
        @(posedge clk);
        s_awvalid <= 1'b0; // De-assert after handshake
        $display("[%0t] AXI Write: Address accepted.", $time);

        // ==========================================================
        // == Phase 2: Data Handshake                              ==
        // ==========================================================
        s_wdata <= data;
        s_wvalid <= 1'b1;
        $display("[%0t] AXI Write: Asserting data. Data=0x%h", $time, data);
        
        // Wait ONLY for the data to be accepted
        wait (s_wready);
        @(posedge clk);
        s_wvalid <= 1'b0; // De-assert after handshake
        $display("[%0t] AXI Write: Data accepted.", $time);

        // ==========================================================
        // == Phase 3: Write Response (B Channel)                  ==
        // ==========================================================
        s_bready <= 1'b1;
        wait (s_bvalid);
        @(posedge clk);
        s_bready <= 1'b0;
        $display("[%0t] AXI Write: Response received. Complete.", $time);
    end
endtask

    // Task to perform an AXI read
    task axi_read(input [31:0] addr, output [31:0] read_data);
        begin
            @(posedge clk);
            s_araddr <= addr;
            s_arvalid <= 1'b1;
            s_rready <= 1'b1;
            $display("[%0t] AXI Read: Addr=0x%h", $time, addr);

            wait (s_arready);
            @(posedge clk);
            s_arvalid <= 1'b0;

            wait (s_rvalid);
            read_data = s_rdata;
            @(posedge clk);
            s_rready <= 1'b0;
            $display("[%0t] AXI Read: Data=0x%h. Complete.", $time, read_data);
        end
    endtask

    //========================================================================
    //==                      Dummy DMA Model                               ==
    //========================================================================
    always @(posedge clk) begin
        if (dma_start) begin
            $display("[%0t] DMA <<< Request received. Addr=0x%h, Len=%d, Dir=%s",
                     $time, dma_addr, dma_len, dma_dir ? "Write to DDR" : "Read from DDR");
            
            // Simulate DMA transfer time (e.g., 10 cycles)
            repeat (10) @(posedge clk);
            
            dma_done <= 1'b1;
            @(posedge clk);
            dma_done <= 1'b0;
            $display("[%0t] DMA >>> Transfer done.", $time);
        end
    end

    //========================================================================
    //==                      Main Test Sequence                            ==
    //========================================================================
    initial begin
        reg [31:0] status_reg;

        // 1. Initial state
        s_awvalid <= 0;
        s_wvalid <= 0;
        s_bready <= 0;
        s_arvalid <= 0;
        s_rready <= 0;
        dma_done <= 0;
        dma_error <= 0;

        // Wait for reset to finish
        wait (rst_n === 1'b1);
        @(posedge clk);

        // 2. Configure the Co-Processor via AXI writes
        $display("\n--- Step 1: Configuring Co-Processor CSRs ---");
        axi_write(REG_VI_BASE_ADDR, 32'h10000000); // Input Vector base address
        axi_write(REG_MI_BASE_ADDR, 32'h20000000); // Input Matrix base address
        axi_write(REG_VO_BASE_ADDR, 32'h30000000); // Output Vector base address
        axi_write(REG_ROWS_ADDR, 32'd32);          // Matrix rows
        axi_write(REG_COLS_ADDR, 32'd32);          // Matrix columns

        // 3. Start the Co-Processor
        $display("\n--- Step 2: Starting Co-Processor ---");
        axi_write(REG_CTRL_ADDR, 32'b1); // Set start bit

        // 4. Wait for completion by polling the status register
        $display("\n--- Step 3: Polling for completion ---");
        status_reg = 0;
        while (status_reg[CSR_STATUS_DONE_BIT] == 0) begin
            #(CLK_PERIOD * 20); // Poll every 20 cycles
            axi_read(REG_STATUS_ADDR, status_reg);
        end
        $display("\n[%0t] >>> Task Done bit detected! <<<", $time);

        // 5. Acknowledge completion by clearing the start bit
        $display("\n--- Step 4: Acknowledging completion ---");
        axi_write(REG_CTRL_ADDR, 32'b0); // Clear start bit

        // 6. Final check
        #(CLK_PERIOD * 10);
        $display("\n--- Testbench Finished ---");
        $finish;
    end

endmodule


//======================================================================
//==                  DUT MODULES (Copied from previous step)         ==
//======================================================================

// NOTE: All DUT modules (Co_Processor, top, CB_Controller, sram, PE_core, write_out)
// are assumed to be defined below this point, exactly as in the previous step.
// For brevity, I will only include the top-level wrapper `Co_Processor` and
// placeholders for the others. In a real setup, you would include the full code.

module Co_Processor (
    input clk, input rst_n, output dma_start, output [31:0] dma_addr,
    output [31:0] dma_len, output dma_dir, input dma_done, input dma_error,
    input [4:0] s_awid, input [31:0] s_awaddr, input [7:0] s_awlen, input [2:0] s_awsize,
    input [1:0] s_awburst, input s_awlock, input [3:0] s_awcache, input [2:0] s_awprot,
    input s_awvalid, output s_awready, input [31:0] s_wdata, input [3:0] s_wstrb,
    input s_wlast, input s_wvalid, output s_wready, output [4:0] s_bid,
    output [1:0] s_bresp, output s_bvalid, input s_bready, input [4:0] s_arid,
    input [31:0] s_araddr, input [7:0] s_arlen, input [2:0] s_arsize, input [1:0] s_arburst,
    input s_arlock, input [3:0] s_arcache, input [2:0] s_arprot, input s_arvalid,
    output s_arready, output [4:0] s_rid, output [31:0] s_rdata, output [1:0] s_rresp,
    output s_rlast, output s_rvalid, input s_rready
);
    wire mac_start_wire, mac_done_wire;
    wire mac_error_wire = 1'b0;

    CB_Controller controller_inst (
        .clk(clk), .rst_n(rst_n), .dma_start(dma_start), .dma_addr(dma_addr),
        .dma_len(dma_len), .dma_dir(dma_dir), .dma_done(dma_done), .dma_error(dma_error),
        .mac_start(mac_start_wire), .mac_done(mac_done_wire), .mac_error(mac_error_wire),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(s_awsize),
        .s_awburst(s_awburst), .s_awlock(s_awlock), .s_awcache(s_awcache), .s_awprot(s_awprot),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_wlast(s_wlast), .s_wvalid(s_wvalid), .s_wready(s_wready), .s_bid(s_bid),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready), .s_arid(s_arid),
        .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_arlock(s_arlock), .s_arcache(s_arcache), .s_arprot(s_arprot), .s_arvalid(s_arvalid),
        .s_arready(s_arready), .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready)
    );
    mac_top mac_top_inst (
        .clk(clk), .srstn(rst_n), .start_processing(mac_start_wire),
        .processing_done(mac_done_wire)
    );
endmodule

