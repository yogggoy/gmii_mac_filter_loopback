`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps

module GMII_MAC(
    input wire reset
    ,input wire sys_clk

    // Transmitter signals
    ,output wire gtx_clk      // Clock signal for gigabit TX signals (125 MHz)
    ,output wire [7:0] txd   // Data to be transmitted
    ,output wire txen        // Transmitter enable
    // ,output wire txer        // Transmitter error (used to intentionally corrupt a packet, if necessary)
    // ,output wire tx_clk      // Clock signal for 10/100 Mbit/s signals

    // Receiver signals
    ,input wire rx_clk         // Received clock signal (recovered from incoming received data)
    ,input wire [7:0] rxd     // Received data
    ,input wire rxdv          // Signifies data received is valid
    ,input wire rxer          // Signifies data received has errors
    // ,input wire col,           // Collision detect (half-duplex connections only)
    // ,input wire cs            // Carrier sense (half-duplex connections only)

    ,output reg [7:0] data_out  // TODO: CDC to sys_clk
);

// ip filter
localparam [31:0]
    ip1 = {8'd192, 8'd168, 8'd0, 8'd1},
    ip2 = {8'd192, 8'd168, 8'd0, 8'd2},
    ip3 = {8'd192, 8'd168, 8'd0, 8'd3},
    ip4 = {8'd192, 8'd168, 8'd0, 8'd4},
    ip5 = {8'd192, 8'd168, 8'd0, 8'd5}
;

localparam [47:0] MAC_DST = 48'h38_6b_1c_1d_f5_65;
// localparam [47:0] MAC_SRC = 48'hFF_FF_FF_11_11_11;

localparam [3:0]  // receiver states
    SM_IDLE      = 4'h0,
    SM_PRMBL_RDY = 4'h1,
    SM_SFD       = 4'h2,
    SM_HEADER    = 4'h3,
    SM_PAYLOAD    = 4'h4,
    SM_CRC       = 4'h5,
    SM_IPG       = 4'h6,
    SM_ERROR     = 4'h7
;

localparam [7:0]
    PREAMBLE = 8'h55,
    START_FRAME_DELIMITER = 8'h5d;



reg [7:0] txd_r;
reg txen_r;
// reg [7:0] rxd_r;
assign txd = txd_r;
assign txen = txen_r;

// rx_clk clock domain registers
reg [3:0] fsm_rcvr, fsm_rcvr_next;
reg [31:0] CRC_received_r; // used for CRC check
reg [3:0] preamble_cntr;
reg [3:0] mac_addr_cntr;
reg [10:0] payload_cntr;
reg [7:0] data_out_rcv;
reg [95:0] mac_src_dst;

wire MAC_is_correct;
assign MAC_is_correct = (MAC_DST == mac_src_dst[95:48]) ? 1'b1 : 1'b0;


//======================= FSM RX START =======================\\

always @(posedge rx_clk) begin : Reseiver_FSM_first
    if (reset)
        fsm_rcvr <= SM_IDLE;
    else
        fsm_rcvr <= fsm_rcvr_next;

end //:  Reseiver_FSM_first


always @(*) begin : Reseiver_FSM_second
    fsm_rcvr_next = SM_IDLE;

    case (fsm_rcvr)
        SM_IDLE :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            // preamble_cntr 7 byte
            else if (preamble_cntr >= 7) fsm_rcvr_next = SM_PRMBL_RDY;
            else fsm_rcvr_next = SM_IDLE;

        SM_PRMBL_RDY :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (rxd != PREAMBLE) fsm_rcvr_next = SM_IDLE;
            else if(rxdv) fsm_rcvr_next = SM_SFD;
            else fsm_rcvr_next = SM_PRMBL_RDY;

        SM_SFD :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if(!rxdv) fsm_rcvr_next = SM_ERROR;
            else if (rxd == PREAMBLE) fsm_rcvr_next = SM_SFD;
            else if (rxd == START_FRAME_DELIMITER) fsm_rcvr_next = SM_HEADER;
            else fsm_rcvr_next = SM_IDLE;

        SM_HEADER :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if(!rxdv) fsm_rcvr_next = SM_ERROR;
            // mac_addr_cntr 2 MAC addr 6 bytes each; 6+6=12
            else if (mac_addr_cntr >= 12) fsm_rcvr_next = SM_PAYLOAD;
            else fsm_rcvr_next = SM_HEADER;

        SM_PAYLOAD :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            // MAC destination filter for example
            // else if (!MAC_is_correct) fsm_rcvr_next = SM_ERROR;
            else fsm_rcvr_next = SM_CRC;

        SM_CRC :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else fsm_rcvr_next = SM_IPG;

        SM_IPG :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else fsm_rcvr_next = SM_ERROR;

        SM_ERROR :
            fsm_rcvr_next = SM_IDLE;

        default :
            fsm_rcvr_next = SM_IDLE;
    endcase
end //: Reseiver_FSM_second


always @(posedge rx_clk) begin : Reseiver_FSM_third
    if (reset) begin
        CRC_received_r <= 32'h0;
        preamble_cntr <= 4'h0;
        mac_addr_cntr <= 4'h0;
        payload_cntr <= 11'b0;
        data_out_rcv <=8'h0;
        mac_src_dst <= 0;
    end
    else begin
        CRC_received_r <= { CRC_received_r[23:0], rxd };
        preamble_cntr <= 4'h0;
        payload_cntr <= 11'b0;
        mac_addr_cntr <= 4'h0;

        case (fsm_rcvr_next)    // third always work on NEXT state
            SM_IDLE :
                if (rxd == PREAMBLE) preamble_cntr <= preamble_cntr + 1'b1;
                else preamble_cntr <= 4'b0;
            SM_PRMBL_RDY :
                if (rxd == PREAMBLE) preamble_cntr <= preamble_cntr;
                else preamble_cntr <= 4'b0;

            SM_SFD : begin
            end

            SM_HEADER : begin
                mac_addr_cntr <= mac_addr_cntr + 1'b1;
                mac_src_dst <= {mac_src_dst[88:0], rxd};
                data_out_rcv <= rxd;
            end
            SM_PAYLOAD : begin
                payload_cntr <= payload_cntr + 1'b1;
                data_out_rcv <= rxd;
                end

            SM_CRC : ;
            SM_IPG : ;
            SM_ERROR : ;
            // S0, S2, S4, S5 : ; // default outputs
        endcase
    end
end // : Reseiver_FSM_third
//======================= FSM RX END =======================\\

endmodule
