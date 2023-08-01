`timescale 1 ns/10 ps  // time-unit = 1 ns, precision = 10 ps
// `include

module GMII_MAC_RX #
(   // ip filter
    parameter [31:0] ip1 = {8'd192, 8'd168, 8'd0, 8'd1},
    parameter [31:0] ip2 = {8'd192, 8'd168, 8'd0, 8'd2},
    parameter [31:0] ip3 = {8'd192, 8'd168, 8'd0, 8'd3},
    parameter [31:0] ip4 = {8'd192, 8'd168, 8'd1, 8'd102},
    parameter [31:0] ip5 = {8'd192, 8'd168, 8'd0, 8'd5}
)
(
    input wire reset

    // Receiver signals
    ,input wire rx_clk         // Received clock signal (recovered from incoming received data)
    ,input wire [7:0] rxd     // Received data
    ,input wire rxdv          // Signifies data received is valid
    ,input wire rxer          // Signifies data received has errors
    // ,input wire col,           // Collision detect (half-duplex connections only)
    // ,input wire cs            // Carrier sense (half-duplex connections only)

    ,output wire [7:0] data_out
    ,output wire IP_is_matched
    ,output reg error
    ,output reg CRC_ok
);


localparam [47:0] MAC_DST = 48'h38_6b_1c_1d_f5_65;
localparam [47:0] MAC_SRC = 48'hFF_FF_FF_11_11_11;

localparam [3:0]  // receiver states
    SM_IDLE      = 4'd0,
    SM_PRMBL_RDY = 4'd1,
    SM_SFD       = 4'd2,
    SM_HEAD_MAC  = 4'd3,
    SM_FR_TYPE   = 4'd4,
    SM_PAYLOAD   = 4'd5,
    SM_CRC       = 4'd6,
    SM_IPG       = 4'd7,
    SM_ERROR     = 4'd8,
    SM_FR_VLAN   = 4'd9,
    SM_IP_DEST   = 4'd10
;

localparam [7:0]
    PREAMBLE = 8'h55,
    START_FRAME_DELIMITER = 8'h5d
;

localparam [15:0]
    IPV4 = 16'h08_00,
    VLAN_TAG = 16'h81_00
;

assign data_out = rxd;

//======== RECEIVER ===========================================
// rx_clk clock domain registers
reg [3:0] fsm_rcvr, fsm_rcvr_next;
reg [31:0] CRC_received_r; // used for CRC check
reg [3:0] preamble_cntr;    // counter for 7 preamble 8'h55
reg [3:0] header_cntr;      // counter for header FSM
reg [3:0] vlan_tags_cntr;   // count how muach Tags in PCKG
reg [10:0] payload_cntr;
reg [95:0] mac_src_dst;     // received MAC DST and MAC SRC
reg [15:0] frame_type;
reg start_frame, frame_end;
reg [63:0] ip_src_dst_r;    // received IPv4 DST and IPv4 SRC

// example how to check MAC
wire MAC_is_correct;
wire [47:0] MAC_src_w, MAC_dst_w;

assign MAC_dst_w = mac_src_dst[95:48];
assign MAC_src_w = mac_src_dst[47:0];
assign MAC_is_correct = (MAC_DST == MAC_dst_w) ? 1'b1 : 1'b0;

wire [31:0] ip_dest, ip_src;
assign ip_src = ip_src_dst_r[63:32];
assign ip_dest = ip_src_dst_r[31:0];

wire ip1_match, ip2_match, ip3_match, ip4_match, ip5_match;
assign ip1_match = (ip1 == ip_dest) ? 1'b1: 1'b0;
assign ip2_match = (ip2 == ip_dest) ? 1'b1: 1'b0;
assign ip3_match = (ip3 == ip_dest) ? 1'b1: 1'b0;
assign ip4_match = (ip4 == ip_dest) ? 1'b1: 1'b0;
assign ip5_match = (ip5 == ip_dest) ? 1'b1: 1'b0;
assign IP_is_matched = ip1_match || ip2_match || ip3_match || ip4_match || ip5_match;


localparam PAYLOAD_MAX = 1500;
wire [5:0] Payload_min;

assign Payload_min = (vlan_tags_cntr == 0) ? 46 :
                     (vlan_tags_cntr == 1) ? 42 :
                     (vlan_tags_cntr == 2) ? 38 :
                     34;       // Max 2 Vtag support

//======================= FSM RX START =======================\\

always @(posedge rx_clk) begin : Reseiver_FSM_first
    if (reset)
        fsm_rcvr <= SM_IDLE;
    else
        fsm_rcvr <= fsm_rcvr_next;

end // :  Reseiver_FSM_first


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
            else if (rxdv) fsm_rcvr_next = SM_SFD;
            else fsm_rcvr_next = SM_PRMBL_RDY;

        SM_SFD :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv) fsm_rcvr_next = SM_ERROR;
            else if (rxd == PREAMBLE) fsm_rcvr_next = SM_SFD;
            else if (rxd == START_FRAME_DELIMITER) fsm_rcvr_next = SM_HEAD_MAC;
            else fsm_rcvr_next = SM_IDLE;

        SM_HEAD_MAC :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv) fsm_rcvr_next = SM_ERROR;
            // header counter MAC_S + MAC_D = 12
            else if (header_cntr >= 12) fsm_rcvr_next = SM_FR_TYPE;
            else fsm_rcvr_next = SM_HEAD_MAC;

        SM_FR_TYPE :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv) fsm_rcvr_next = SM_ERROR;
            else if (preamble_cntr >= 2)  begin
                if (frame_type == VLAN_TAG) fsm_rcvr_next = SM_FR_VLAN;
                else fsm_rcvr_next = SM_PAYLOAD; // (frame_type == IPV4)
            end
            else fsm_rcvr_next = SM_FR_TYPE;

        SM_FR_VLAN :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv) fsm_rcvr_next = SM_ERROR;
            else if (header_cntr >= 2) fsm_rcvr_next = SM_FR_TYPE;
            else fsm_rcvr_next = SM_FR_VLAN;

        SM_PAYLOAD :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            // MAC destination filter for example
            // else if (!MAC_is_correct) fsm_rcvr_next = SM_ERROR;
            else if (payload_cntr == 12) fsm_rcvr_next = SM_IP_DEST;
            else if (payload_cntr >= PAYLOAD_MAX) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv)
                if (payload_cntr <= Payload_min)
                    fsm_rcvr_next = SM_ERROR;
                else fsm_rcvr_next = SM_CRC;
            else fsm_rcvr_next = SM_PAYLOAD;

        SM_IP_DEST :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else if (!rxdv) fsm_rcvr_next = SM_ERROR;
            else if (payload_cntr == 20) fsm_rcvr_next = SM_PAYLOAD;
            else fsm_rcvr_next = SM_IP_DEST;

        SM_CRC :
            if (rxer) fsm_rcvr_next = SM_ERROR;
            else fsm_rcvr_next = SM_IPG;

        SM_ERROR :
            fsm_rcvr_next = SM_IPG;

        SM_IPG :
            fsm_rcvr_next = SM_IDLE;

        default :
            fsm_rcvr_next = SM_IDLE;
    endcase
end // : Reseiver_FSM_second


always @(posedge rx_clk) begin : Reseiver_FSM_third
    if (reset) begin
        CRC_received_r <= 32'h0;
        preamble_cntr <= 4'h0;
        payload_cntr <= 11'b0;
        header_cntr <= 4'h0;
        start_frame <= 1'b0;
        frame_end <= 1'b0;
        frame_type <= 16'h0;
        mac_src_dst <= 96'h0;
        ip_src_dst_r <= 64'b0;
        vlan_tags_cntr <= 4'b0;
        error <= 1'b0;
    end
    else begin
        CRC_received_r <= { CRC_received_r[23:0], rxd };
        preamble_cntr <= 4'h0;
        payload_cntr <= 11'b0;
        header_cntr <= 4'h0;
        start_frame <= 1'b0;
        frame_end <= 1'b0;

        case (fsm_rcvr_next)    // third always work on NEXT state
            SM_IDLE : begin
                vlan_tags_cntr <= 4'b0;
                if (rxd == PREAMBLE) preamble_cntr <= preamble_cntr + 1'b1;
                else preamble_cntr <= 4'b0;
            end

            SM_PRMBL_RDY : begin
                error <= 0;
                if (rxd == PREAMBLE) preamble_cntr <= preamble_cntr;
                else preamble_cntr <= 4'b0;
            end

            SM_SFD :
                if (rxd == START_FRAME_DELIMITER)
                    start_frame <= 1'b1;

            SM_HEAD_MAC : begin
                header_cntr <= header_cntr + 1'b1;
                mac_src_dst <= {mac_src_dst[88:0], rxd};
            end

            SM_FR_TYPE : begin
                // use preamble_cntr just like byte counter
                preamble_cntr <= preamble_cntr + 1'b1;
                frame_type <= {frame_type[7:0], rxd};
            end

            SM_FR_VLAN : begin
                header_cntr <= header_cntr + 1'b1;
                if (header_cntr == 1)
                    vlan_tags_cntr <= vlan_tags_cntr +1'b1;
            end

            SM_PAYLOAD : begin
                payload_cntr <= payload_cntr + 1'b1;
                end

            SM_IP_DEST : begin
                payload_cntr <= payload_cntr + 1'b1;
                ip_src_dst_r <= {ip_src_dst_r[55:0], rxd};
            end

            SM_CRC : frame_end <= 1'b1;
            SM_IPG : ;
            SM_ERROR : begin
                frame_end <= 1'b1;
                error <= 1'b1;
            end

        endcase
    end
end // : Reseiver_FSM_third
//======================= FSM RX END =======================\\


endmodule
