// --------------------------------------------------
// Document:  pjdl_send.sv
// Project:   PJON_ASIC/PJDL
// Function:  sending part of the PJDL strategy of PJON
// Autor:     Pius Sieber
// Date:      06.04.2025
// Comments:  -
// --------------------------------------------------

module pjdl_send #(
    parameter int BufferSize = 2, // size of the FIFO buffer, minimum size is 1

    parameter type                         axis_req_t  = logic,
    parameter type                         axis_rsp_t  = logic
)(
    input   logic clk_i,
    input   logic rst_ni,
    input   logic enable_i,   // allow sending (in contrast to rst_ni,
                              // buffer and axi-stream still work when enable_i is low)

    // AXI Stream Bus Receiver Port to conect to Layer 3 or wrapper
    input axis_req_t axis_read_req_i,
    output axis_rsp_t axis_read_rsp_o,

    output logic sending_in_progress_o,
    output logic start_ack_receiving_o, // output to pjdl_receive to start receiving an ack

    // HW interface
    input   logic pjon_i,
    output  logic pjon_o,
    output  logic pjon_en_o,

    // PJDL specification (mode dependent)
    input   logic [19:0] pjdl_spec_preamble_i,
    input   logic [13:0] pjdl_spec_pad_i,
    input   logic [11:0] pjdl_spec_data_i
);
    `include "common_cells/registers.svh"

    typedef enum logic [2:0] {Idle, Sync, Data, PrepareAck, SendAckReq, Disabled, SendDelay} send_state_t;
    send_state_t send_state_q, send_state_d;
    logic [3:0] bit_counter_q, bit_counter_d;
    logic [19:0] clk_counter_q, clk_counter_d; // 20 bits for a maximum preamble size of 11000us 
                                               // at 80MHz
    logic [19:0] clk_counter_limit_q, clk_counter_limit_d;
    logic [7:0] send_byte_q, send_byte_d;

    logic [7:0] next_byte;
    logic next_is_last;
    logic next_is_ack;
    logic next_is_ack_req;
    logic next_is_empty_last;

    logic current_is_last_q, current_is_last_d;
    logic pop_next_byte_d, pop_next_byte_q;

    logic pjon_out_q, pjon_out_d;
    logic start_ack_receiving_q, start_ack_receiving_d;
    logic go_to_idle_q, go_to_idle_d;
    logic go_to_send_delay_q, go_to_send_delay_d;

    // Specification index constants
    localparam int unsigned PJDL_PREAMB   = 0;  // PJDL Preamble bit
    localparam int unsigned PJDL_PAD      = 1;  // PJDL Pad bit
    localparam int unsigned PJDL_DATA     = 2;  // PJDL Data bit

    logic buffer_full, buffer_empty;

    assign axis_read_rsp_o.tready = !buffer_full && rst_ni;

    assign sending_in_progress_o = !((send_state_q == Idle)
        || (send_state_q == Disabled) || (send_state_q == SendDelay));
    assign start_ack_receiving_o = start_ack_receiving_q;

    assign pjon_o = pjon_out_q;

    // the following axi stream signals are not used in this module:
    // tstrb // position byte not supported (ignores position)
    // tid   // no source and destination signaling supported
    // tdest // no source and destination signaling supported

    fifo_v3 #(
        .DATA_WIDTH(12), // 1 bit for empty last, 1 bits for user, 1 bit for tlast 
                         // and 8 bits for data
        .DEPTH(BufferSize)
    ) buffer_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .flush_i(1'b0),
        .testmode_i(1'b0),
        .usage_o( ),

        .data_i({!axis_read_req_i.t.keep, axis_read_req_i.t.user[1:0], 
                  axis_read_req_i.t.last, axis_read_req_i.t.data[7:0]}), // Bit 11 indicates 
                                                                         // a last byte without data
        .push_i(axis_read_req_i.tvalid && axis_read_rsp_o.tready 
                && (axis_read_req_i.t.keep || axis_read_req_i.t.last) 
                && axis_read_req_i.t.strb), // push according to axi stream specification

        .data_o({next_is_empty_last, next_is_ack_req, next_is_ack, next_is_last, next_byte[7:0]}),
        .pop_i(pop_next_byte_q),

        .full_o(buffer_full),
        .empty_o(buffer_empty)
    );

    always_comb begin
        bit_counter_d = bit_counter_q;
        clk_counter_limit_d = clk_counter_limit_q;
        pjon_out_d = pjon_out_q;

        if(send_state_q == Idle) begin
            pjon_out_d = 1'b0;
            clk_counter_d = 0;
            bit_counter_d = 0;
            clk_counter_limit_d = 0;
        end else if (send_state_q == Disabled) begin
            pjon_out_d = 1'b0;
            clk_counter_d = 0;
            bit_counter_d = 0;
            clk_counter_limit_d = 0;
        end else begin
            clk_counter_d = clk_counter_q + 1;
        
            if(clk_counter_q == clk_counter_limit_q) begin
                clk_counter_d = 0;
                bit_counter_d = bit_counter_q + 1;

                if(send_state_q == Sync) begin
                    if(bit_counter_q == 4'b0) begin // Preamble
                        pjon_out_d = 1'b1;
                        clk_counter_limit_d = pjdl_spec_preamble_i;
                    end else if((bit_counter_q == 4'h1) || (bit_counter_q == 4'h3) 
                        || (bit_counter_q == 4'h5)) begin // Sync 1
                        pjon_out_d = 1'b1;
                        clk_counter_limit_d = {6'b0, pjdl_spec_pad_i};
                    end else begin // Sync 0
                        pjon_out_d = 1'b0;
                        clk_counter_limit_d = {8'b0, pjdl_spec_data_i};
                    end
                    if(bit_counter_q == 4'h6) begin // last bit
                        bit_counter_d = 0;
                    end
                end
                if(send_state_q == Data) begin
                    if(bit_counter_q == 4'h0) begin // Sync 1
                        pjon_out_d = 1'b1;
                        clk_counter_limit_d = {6'b0, pjdl_spec_pad_i};
                    end else if(bit_counter_q == 4'h1) begin // Sync 0
                        pjon_out_d = 1'b0;
                        clk_counter_limit_d = {8'b0, pjdl_spec_data_i};
                    end else if((bit_counter_q > 4'h1)) begin // Data-Bits
                        pjon_out_d = send_byte_q[bit_counter_q - 2];
                        clk_counter_limit_d = {8'b0, pjdl_spec_data_i};
                    end
                    if(bit_counter_q == 4'h9) begin // last bit
                        bit_counter_d = 0;
                    end
                end
                if(send_state_q == PrepareAck) begin
                    pjon_out_d = 1'b0;
                    if(bit_counter_q == 4'h0) begin
                        clk_counter_limit_d = (pjdl_spec_pad_i*2);
                    end else if (bit_counter_q ==4'h1) begin
                        clk_counter_limit_d = {8'b0, pjdl_spec_data_i}/4;
                    end else if (bit_counter_q == 4'h2) begin
                        bit_counter_d = 0;
                    end
                end
                if(send_state_q == SendAckReq) begin
                    if(bit_counter_q[0] == 1'b0) begin // on even numers of bits
                        pjon_out_d = 1'b0;
                        clk_counter_limit_d = 2*pjdl_spec_pad_i;
                    end else begin
                        pjon_out_d = 1'b1;
                        clk_counter_limit_d = {8'b0, pjdl_spec_data_i}/4;
                    end
                end
            end
        end
        if(send_state_q == PrepareAck) begin
            if((((bit_counter_q == 4'h1) && (pjon_i==1'b1)) 
                || ((bit_counter_q == 4'h2) && (pjon_i == 1'b0))) 
                && (clk_counter_limit_q != clk_counter_q)) begin // bit counter q is already one 
                                                                 // step ahead in this case 
                                                                 // (limit not reached)
                clk_counter_d = clk_counter_limit_q; // go to the next step when the input signal 
                                                     // is already at the right level
            end
        end
        if(send_state_q == SendDelay) begin
            pjon_out_d = 1'b0;
            clk_counter_limit_d = pjdl_spec_pad_i*2; // Delay with length of one pad-bit
            bit_counter_d = '0;
            if(clk_counter_q == clk_counter_limit_q)begin
                clk_counter_limit_d = '0;
            end
        end
    end


    always_comb begin
        send_state_d = send_state_q;
        pjon_en_o = 1'b0;
        pop_next_byte_d = 1'b0;
        start_ack_receiving_d = 1'b0;

        send_byte_d = send_byte_q;
        current_is_last_d = current_is_last_q;
        go_to_idle_d = go_to_idle_q;
        go_to_send_delay_d = go_to_send_delay_q;

        if((clk_counter_q == clk_counter_limit_q) && go_to_idle_q) begin
            go_to_idle_d = 1'b0;
            send_state_d = Idle;
        end
        if((clk_counter_q == clk_counter_limit_q) && go_to_send_delay_q) begin
            go_to_send_delay_d = 1'b0;
            send_state_d = SendDelay;
        end
        if(send_state_q == SendDelay) begin
            go_to_idle_d = 1'b1;
        end

        // sync or byte done, ready to load next byte ?
        if(((send_state_q == Sync) && (bit_counter_q == 4'h6))
            || ((send_state_q == Data) && (bit_counter_q == 4'h9)) 
            || ((send_state_q == PrepareAck) && (bit_counter_q == 4'h2))) begin 
            if(clk_counter_q == clk_counter_limit_q) begin // wait for last bit to be sent
                if(next_is_empty_last) begin
                    pop_next_byte_d = 1'b1;
                end
                if(next_is_ack_req) begin
                    go_to_idle_d = 1'b1;
                end else if ((current_is_last_q==1'b1) || (next_is_empty_last)) begin
                    current_is_last_d = 1'b0;
                    go_to_send_delay_d = 1'b1;
                end else begin
                    send_state_d = Data;
                    if(buffer_empty == 1'b1) begin
                        send_byte_d = 8'h00;
                    end else begin
                        send_byte_d = next_byte;
                        current_is_last_d = next_is_last;
                        pop_next_byte_d = 1'b1;
                    end
                end
            end
        end

        case (send_state_q)
            default: begin // Idle
                pjon_en_o = 1'b0;
                if (buffer_empty  == 1'b0) begin // buffer is not empty, start sending
                    if(next_is_ack==1'b1) begin
                        send_state_d = PrepareAck;
                    end else if (next_is_ack_req) begin
                        send_state_d = SendAckReq;
                        pop_next_byte_d = 1'b1;
                        send_byte_d = next_byte; // specifies the number of bits to send 
                                                 // bevor the timeout
                    end else if(!pop_next_byte_q)begin // do not start new sending if buffer-pop 
                                                       // is still active
                        send_state_d = Sync;
                    end
                end
            end

            Sync: begin
                pjon_en_o = 1'b1;
            end

            Data: begin
                pjon_en_o = 1'b1;
            end

            PrepareAck: begin
                pjon_en_o = 1'b0;
            end

            SendAckReq: begin
                if(bit_counter_q[0] == 1'b0) begin // on even numers of bits
                    pjon_en_o = 1'b1;
                end else begin
                    pjon_en_o = 1'b0;
                    if(pjon_i == 1'b1) begin
                        start_ack_receiving_d = 1'b1;
                    end
                end
                if({4'b0, bit_counter_q}/2 == send_byte_q) begin // timeout defined by input value
                    go_to_idle_d = 1'b1;
                end
            end

            Disabled: begin
                if(enable_i) begin
                    send_state_d = Idle;
                end
                pjon_en_o = 1'b0;

                send_byte_d = 0;
                current_is_last_d = 0;
                go_to_idle_d = 1'b0;
            end

            SendDelay: begin
                pjon_en_o =  1'b0;
            end
        endcase

        if(!enable_i) begin
            send_state_d = Disabled;
        end
    end

    `FF(send_state_q, send_state_d, Idle);
    `FF(bit_counter_q, bit_counter_d, '0);
    `FF(clk_counter_q, clk_counter_d, '0);
    `FF(send_byte_q, send_byte_d, '0);
    `FF(clk_counter_limit_q, clk_counter_limit_d, '0);
    `FF(pop_next_byte_q, pop_next_byte_d, 0);
    `FF(current_is_last_q, current_is_last_d, '0);
    `FF(pjon_out_q, pjon_out_d, '0);
    `FF(start_ack_receiving_q, start_ack_receiving_d, '0);
    `FF(go_to_idle_q, go_to_idle_d, '0);
    `FF(go_to_send_delay_q, go_to_send_delay_d, '0);
endmodule