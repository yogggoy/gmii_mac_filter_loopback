`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps

module GMII_MAC_tb;

localparam period = 5;

reg reset = 0;
reg sys_clk = 0;

wire [7:0] txd;
wire gtx_clk, txen;

reg [7:0] rxd = 8'b0;
reg rx_clk = 0;
reg rxdv = 0;
reg rxer = 0;

integer i;
reg [7:0] test_seq [25:0];

initial begin
    // Dest MAC
    test_seq[0]  = 8'h38;
    test_seq[1]  = 8'h6b;
    test_seq[2]  = 8'h1c;
    test_seq[3]  = 8'h1d;
    test_seq[4]  = 8'hf5;
    test_seq[5]  = 8'h65;
    // Src MAC
    test_seq[6]  = 8'h04;
    test_seq[7]  = 8'h95;
    test_seq[8]  = 8'he6;
    test_seq[9]  = 8'h00;
    test_seq[10] = 8'hed;
    test_seq[11] = 8'hac;
    // IPv4
    test_seq[12] = 8'h08;
    test_seq[13] = 8'h00;
    // TCP
    test_seq[14] = 8'h45;
    test_seq[15] = 8'h00;

    test_seq[16] = 8'h4;
    test_seq[17] = 8'h4;
    test_seq[18] = 8'h3;
    test_seq[19] = 8'h4;
    test_seq[20] = 8'h4;
    test_seq[21] = 8'h4;
    test_seq[22] = 8'h1;
    test_seq[23] = 8'h2;
    test_seq[24] = 8'h6;
    test_seq[25] = 8'h4;
end

always begin
    #period
    rx_clk = ~rx_clk;
    #2.5
    sys_clk = ~sys_clk;
end

initial begin
    // start transact RX
    #0      rxd = 8'h1;
    #period reset = 1;
    #50     @(posedge sys_clk) reset = 0;
    // test preamble 7 byte
            @(posedge rx_clk) rxd = 8'h55;
    #120    @(posedge rx_clk) rxd = 8'h11;
    // test preamble and data_valid
    #20     @(posedge rx_clk) rxd = 8'h55;
    #50     @(posedge rx_clk) rxdv = 1;

    // preamble sequence
    for (i=1; i < 8; i=i+1) begin
        @(posedge rx_clk)
            rxd = 8'h55;
    end

    // START_FRAME_DELIMITER
    @(posedge rx_clk) rxd = 8'h5D;

    // Header Frame
    for (i=0; i < 26; i=i+1) begin
        @(posedge rx_clk)
            rxd = test_seq[i];
    end

    #200
    $finish;
end

// initial #2000 $finish;


initial
begin
    $dumpfile("out.vcd");
    $dumpvars(0, GMII_MAC_tb);
end


GMII_MAC GMII_MAC_tb_inst(
    .reset   (reset),      // input wire
    .sys_clk (sys_clk),        // input wire
    .gtx_clk (gtx_clk),     // output wire
    .txd     (txd),        // output wire [7:0]
    .txen    (txen),       // output wire
    .rx_clk  (rx_clk),      // input wire
    .rxd     (rxd),        // input wire  [7:0]
    .rxdv    (rxdv),       // input wire
    .rxer    (rxer)        // input wire
);

endmodule
