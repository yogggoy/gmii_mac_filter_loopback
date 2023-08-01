`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps

module GMII_MAC_tb;

localparam period = 8;  // 125Mhz period 8ns;

reg reset = 0;
reg sys_clk = 0;

wire [7:0] txd;
wire gtx_clk, txen;

reg [7:0] rxd = 8'b0;
reg rx_clk = 0;
reg rxdv = 0;
reg rxer = 0;

integer i, j;

reg [7:0] ex2_memory [0:287];
initial begin
    $readmemh("eth_frame.mem", ex2_memory);
    // for (i=0; i < 20; i=i+1)
    //     $display("R] %00h ", ex2_memory[i]);
end

always begin
    #2  rx_clk = ~rx_clk;
    #2  sys_clk = ~sys_clk;
end

initial begin
    // start transact RX
    #period reset = 1;
    #50     @(posedge sys_clk) reset = 0;

    // test preamble 7 byte
    #30     @(posedge rx_clk) rxd = 8'h55;
    #120    @(posedge rx_clk) rxd = 8'h11;
    // test preamble and data_valid
    #20     @(posedge rx_clk) rxd = 8'h55;
    #50     @(posedge rx_clk) rxdv = 1;

    // preamble sequence
    for (i=1; i < 8; i=i+1) @(posedge rx_clk) rxd = 8'h55;
    @(posedge rx_clk) rxd = 8'h5D; // START_FRAME_DELIMITER

    // Header Frame
    for (i=0; i < 288; i=i+1)
        @(posedge rx_clk) rxd = ex2_memory[i];

    @(posedge rx_clk) rxdv = 0;

    #250
    $finish;
end


initial
begin
    $dumpfile("out.vcd");
    $dumpvars(0, GMII_MAC_tb);
end

GMII_MAC_RX # (
    .ip2({8'd192, 8'd168, 8'd100, 8'd102})
) GMII_MAC_RX_inst (
    .reset   (reset),      // input wire
    .rx_clk  (rx_clk),      // input wire
    .rxd     (rxd),        // input wire  [7:0]
    .rxdv    (rxdv),       // input wire
    .rxer    (rxer)        // input wire
);

endmodule
