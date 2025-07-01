// --------------------------------------------------
// Document:  pjdl_receive.sv
// Project:   PJON_ASIC/PJDL
// Function:  receiving part of the PJDL strategy of PJON
// Autor:     Pius Sieber
// Date:      07.04.2025
// Comments:  -
// --------------------------------------------------

module pjdl_receive #(
    parameter int BufferSize = 2, // size of the FIFO buffer, minimum size is 1

    parameter type                  axis_req_t  = logic,
    parameter type                  axis_rsp_t  = logic
)(
    input   logic clk_i,
    input   logic rst_ni,
    input   logic enable_i,   // allow receiving (in contrast to rst_ni, buffer and axi-stream 
                              // still works when enable_i is low)

    // AXI Stream Bus Receiver Port to conect to Layer 3 or wrapper
    input axis_rsp_t axis_write_rsp_i,
    output axis_req_t axis_write_req_o,

    // Status signal
    output logic receiving_in_progress_o,

    // Interface to pjdl sending part to coordinate ack receiving
    input logic start_ack_receiving_i,

    // HW interface
    input   logic pjon_i,

    // PJDL specification (mode dependent)
    input   logic [19:0] pjdl_spec_preamble_i,
    input   logic [13:0] pjdl_spec_pad_i,
    input   logic [11:0] pjdl_spec_data_i,
    input   logic [12:0] pjdl_spec_acceptance_i // minimum length of a pad to be accepted
);
    `include "common_cells/registers.svh"

    // States of the receiving state-event machine
    typedef enum logic [1:0] {Idle, Sync, Data} receive_state_t;
    receive_state_t receive_state_q, receive_state_d;

    logic pjon_in_q, pjon_in_d, last_pjon_in_q, last_pjon_in_d;
    logic [19:0] clk_counter_q, clk_counter_d; // 20 bits for a maximum preamble size of 
                                               // 11000us at 80MHz
    logic [3:0] bit_counter_q, bit_counter_d; // 4 bits for a maximum value of 8 bits
    logic [7:0] received_byte_q, received_byte_d;

    logic byte_saved_q, byte_saved_d;
    logic byte_to_save_is_last_q, byte_to_save_is_last_d;
    logic [7:0] byte_to_save_q, byte_to_save_d;
    logic push_byte_q, push_byte_d;

    logic buffer_empty;

    assign pjon_in_d = pjon_i;
    assign last_pjon_in_d = pjon_in_q || start_ack_receiving_i; // previous pjon_in value
                                                                // has to be 1 on start of ack receving

    // the following axi stream signals are not used in this module:
    assign axis_write_req_o.t.strb = 1'b1; // only send data bytes
    assign axis_write_req_o.t.keep = 1'b1; // keep all packets
    assign axis_write_req_o.t.id = 1'b0;   // no source and destination signaling supported
    assign axis_write_req_o.t.dest = 1'b0; // no source and destination signaling supported
    assign axis_write_req_o.t.user = 2'b0; // no user data needed

    // axi-stream signal is ready to receive data as long as the buffer is not empty and reset
    // is not active
    assign axis_write_req_o.tvalid = ~buffer_empty && rst_ni;

    // FIFO buffer to save received bytes until they can be sent via AXI-Stream
    fifo_v3 #(
        .DATA_WIDTH(9), // 1 bit for tlast and 8 bits for data
        .DEPTH(BufferSize)
    ) buffer_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .flush_i(1'b0),
        .testmode_i(1'b0),
        .usage_o( ),

        .data_i({byte_to_save_is_last_q, byte_to_save_q}),
        .push_i(push_byte_q), 

        .data_o({axis_write_req_o.t.last, axis_write_req_o.t.data[7:0]}),
        .pop_i(axis_write_req_o.tvalid && axis_write_rsp_i.tready), // pop according to 
                                                                    // axi-stream specification

        .full_o( ), // have to ignore full buffer as we can't stop pjon receiving
        .empty_o(buffer_empty)
    );

    // Data path logic
    always_comb begin
        bit_counter_d = bit_counter_q;
        clk_counter_d = clk_counter_q;
        byte_saved_d = byte_saved_q;
        byte_to_save_is_last_d = byte_to_save_is_last_q;
        push_byte_d = 1'b0;
        byte_to_save_d = byte_to_save_q;
        received_byte_d = received_byte_q;

        case (receive_state_q)
            default: begin // Idle
                clk_counter_d = 0;
                bit_counter_d = 0;

                byte_to_save_is_last_d = 1'b1;
                if(byte_saved_q == 1'b0) begin
                    byte_saved_d = 1'b1;
                    push_byte_d = 1'b1;
                end
                if(start_ack_receiving_i == 1'b1) begin
                    bit_counter_d = 3;
                end
            end
            Sync: begin
                if((pjon_in_q == 1'b0) && (last_pjon_in_q == 1'b1)) begin // negative edge
                    if(clk_counter_q > {7'b0, pjdl_spec_acceptance_i}) begin
                        bit_counter_d = bit_counter_q + 1;
                    end
                end
                if(pjon_in_q != last_pjon_in_q) begin // edge detected
                    clk_counter_d = 0;
                end else begin
                    clk_counter_d = clk_counter_q + 1;
                end
                if((bit_counter_q == 4) && (clk_counter_q == ({8'b0, pjdl_spec_data_i}/2))) begin
                    bit_counter_d = 0;
                    clk_counter_d = 0;
                end
            end
            Data: begin
                clk_counter_d = clk_counter_q + 1;

                if(bit_counter_q == 8) begin
                    byte_to_save_d = received_byte_q;
                    byte_saved_d = 1'b0;
                    if((pjon_in_q == 1'b1) && ((last_pjon_in_q == 1'b0) 
                        || (clk_counter_q == {8'b0, pjdl_spec_data_i}))) begin
                        bit_counter_d = 3;
                        clk_counter_d = 0;
                    end
                end else begin
                    if(clk_counter_q == {8'b0, pjdl_spec_data_i}) begin
                        clk_counter_d = 0;
                        bit_counter_d = bit_counter_q + 1;
                        received_byte_d = {pjon_in_q, received_byte_q[7:1]};
                    end

                    byte_to_save_is_last_d = 1'b0;
                    if(byte_saved_q == 1'b0) begin
                        byte_saved_d = 1'b1;
                        push_byte_d = 1'b1;
                    end
                end
            end
        endcase
    end

    // State-Event machine
    always_comb begin
        receive_state_d = receive_state_q;

        case (receive_state_q)
            Idle: begin
                receiving_in_progress_o = 1'b0;
                if(pjon_in_q == 1'b1) begin
                    receive_state_d = Sync;
                end
                if(start_ack_receiving_i == 1'b1) begin // ToDo: ack request should continue 
                                                        // if sync is not detected
                    receive_state_d = Sync;
                end
            end

            Sync: begin
                receiving_in_progress_o = 1'b1;
                if((bit_counter_q == 4) && (clk_counter_q == ({8'b0, pjdl_spec_data_i}/2))) begin
                    receive_state_d = Data;
                end
                if((pjon_in_q == 1'b0) && ((last_pjon_in_q == 1'b1))) begin // negative edge
                     if(clk_counter_q <= {7'b0, pjdl_spec_acceptance_i}) begin // ToDo: improve to 
                                                                               // support short zero 
                                                                               // values inbetween
                        receive_state_d = Idle;
                    end
                end
                if((pjon_in_q == 1'b1) && ((last_pjon_in_q == 1'b0))) begin // positive edge
                    if(clk_counter_q < ({8'b0, pjdl_spec_data_i}/2)) begin // check that we read 
                                                                           // long enough zero after
                                                                           // sync pad
                        receive_state_d = Idle;
                    end
                end
                // if no more data received
                if((pjon_in_q == 1'b0) && (clk_counter_q>=({5'b0, pjdl_spec_pad_i}<<1))) begin
                    receive_state_d = Idle;
                end
            end

            Data: begin
                receiving_in_progress_o = 1'b1;
                if(bit_counter_q == 8) begin
                    if(((pjon_in_q == 1'b1) && (last_pjon_in_q == 1'b0)) 
                        || ((pjon_in_q == 1'b1) && (clk_counter_q == {8'b0, pjdl_spec_data_i}))) begin
                        receive_state_d = Sync;
                    end
                    // if no more data received:
                    if((pjon_in_q == 1'b0) && (clk_counter_q>={6'b0, pjdl_spec_pad_i})) begin 
                        receive_state_d = Idle;
                    end
                end
            end
            default: begin
                receive_state_d = receive_state_q;
                receiving_in_progress_o = 1'b1;
            end
        endcase

        if(!(enable_i || start_ack_receiving_i)) begin
            receive_state_d = Idle;
        end
    end

    `FF(receive_state_q, receive_state_d, Idle);
    `FF(pjon_in_q, pjon_in_d, '0);
    `FF(last_pjon_in_q, last_pjon_in_d, '0);
    `FF(clk_counter_q, clk_counter_d, '0);
    `FF(received_byte_q, received_byte_d, '0);
    `FF(bit_counter_q, bit_counter_d, '0);
    `FF(byte_saved_q, byte_saved_d, 1'b1);
    `FF(byte_to_save_is_last_q, byte_to_save_is_last_d, '0);
    `FF(byte_to_save_q, byte_to_save_d, '0);
    `FF(push_byte_q, push_byte_d, '0);
endmodule