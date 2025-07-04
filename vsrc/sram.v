//****************************************************************************
// Description:
// A generic and flexible synchronous SRAM model.
//
// Features:
// - Configurable data width and address depth via parameters.
// - Separate read and write addresses.
// - Active-low chip select (csb) and write enable (wsb).
// - Synchronous read and write operations on the positive edge of the clock.
// - Models a small propagation delay on the read data output for simulation.
//   (Requires `cycle_period to be defined, typically in a testbench).
// - Includes a 'load_mem' task for easy memory initialization in simulations.
//
// Parameters:
// - DATA_WIDTH: Defines the bit-width of each memory location.
// - ADDR_WIDTH: Defines the bit-width of the address bus, which in turn
//               determines the depth of the memory (Depth = 2^ADDR_WIDTH).
//****************************************************************************
module sram #(
    parameter DATA_WIDTH = 512,
    parameter ADDR_WIDTH = 6
)
(
    input clk,
    input csb,                      // Chip Select (active low)
    input wsb,                      // Write Enable (active low)
    input [DATA_WIDTH-1:0] wdata,   // Write data
    input [ADDR_WIDTH-1:0] waddr,   // Write address
    input [ADDR_WIDTH-1:0] raddr,   // Read address
    output reg [DATA_WIDTH-1:0] rdata // Read data
);

    // Calculate the memory depth based on the address width
    localparam DEPTH = 1 << ADDR_WIDTH;

    // The core memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Internal register to hold the latched read data before output delay
    reg [DATA_WIDTH-1:0] _rdata;

    // Synchronous write logic:
    // Writes data to the specified address on the positive clock edge
    // if both chip select and write enable are active (low).
    always @(posedge clk) begin
        if (~csb && ~wsb) begin
            mem[waddr] <= wdata;
        end
    end

    // Synchronous read logic:
    // Latches the data from the specified read address into an internal
    // register on the positive clock edge if chip select is active.
    always @(posedge clk) begin
        if (~csb) begin
            _rdata <= mem[raddr];
        end
    end

    // Read data output with propagation delay:
    // This combinational block assigns the latched data to the output port,
    // modeling a small propagation delay.
    // Note: `cycle_period must be defined (e.g., `define cycle_period 10)
    // in your testbench or global defines for the delay to work.
    always @* begin
        // rdata = #(`cycle_period * 0.2) _rdata;
        // For synthesis or if no delay modeling is needed, use:
        rdata = _rdata;
    end

    // Task for pre-loading memory content.
    // This is useful for initializing the SRAM from a testbench.
    task load_mem(
        input [ADDR_WIDTH-1:0] index,
        input [DATA_WIDTH-1:0] data_input
    );
        begin
            mem[index] = data_input;
        end
    endtask

endmodule
