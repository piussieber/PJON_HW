// --------------------------------------------------
// Document:  pjon_addressing.sv
// Project:   PJON_ASIC/pjon_addressing
// Function:  Address filter to keep unrelated packets from beeing sent to Layer 3 in software
//            This module can be placed directly in series to the pjdl-module to be used.
// Autor:     Pius Sieber
// Date:      01.07.2025
// Comments:  -
// --------------------------------------------------

module pjon_addressing #(
    parameter int BufferSize = 1, // size of the FIFO buffer, minimum size is 1

    parameter type axis_req_t  = logic,
    parameter type axis_rsp_t  = logic
)(
    input   logic clk_i,
    input   logic rst_ni,

    // send-axi-connection to wrapper
    input axis_req_t axis_read_req_i,
    output axis_rsp_t axis_read_rsp_o,

    // send-axi-connection from layer 2 module
    output axis_req_t axis_read_req_o,
    input axis_rsp_t axis_read_rsp_i,
    
    // receive-axi-connection from layer 2 module
    output axis_rsp_t axis_write_rsp_o,
    input axis_req_t axis_write_req_i,

    // receive-axi-connection to wrapper
    input axis_rsp_t axis_write_rsp_i,
    output axis_req_t axis_write_req_o,

    input logic start_ack_receiving_i, // when ack_receiving is active, address checking isn't needed

    // PJON Settings
    input logic [7:0] pjon_device_id_i, // PJON Address
    input logic router_mode_i
);
    `include "common_cells/registers.svh"

    logic buffer_empty, buffer_full;
    logic preprocessing_done_q, preprocessing_done_d;
    logic data_irrelevant_q, data_irrelevant_d;
    logic ack_receiving_active_q, ack_receiving_active_d;

    assign axis_read_req_o = axis_read_req_i;
    assign axis_read_rsp_o = axis_read_rsp_i;

    assign axis_write_rsp_o.tready = !buffer_full;
    assign axis_write_req_o.tvalid = !buffer_empty && !data_irrelevant_q && preprocessing_done_q;

    // FIFO buffer to save received bytes until they can be sent further to wrapper
    fifo_v3 #(
        .DATA_WIDTH(9), // 1 bit for tlast and 8 bits for data
        .DEPTH(BufferSize)
    ) buffer_fifo (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .flush_i(1'b0),
        .testmode_i(1'b0),
        .usage_o( ),

        .data_i({axis_write_req_i.t.last, axis_write_req_i.t.data[7:0]}),
        .push_i(axis_write_req_i.tvalid && axis_write_rsp_o.tready), 

        .data_o({axis_write_req_o.t.last, axis_write_req_o.t.data[7:0]}),
        .pop_i((axis_write_req_o.tvalid && axis_write_rsp_i.tready) || data_irrelevant_q), // pop according to 
                                                                    // axi-stream specification

        .full_o(buffer_full), // have to ignore full buffer as we can't stop pjon receiving
        .empty_o(buffer_empty)
    );

    // create ack_receving_active-signal
    always_comb begin
        ack_receiving_active_d = ack_receiving_active_q;
        if (start_ack_receiving_i) begin 
            ack_receiving_active_d = 1'b1;
        end else if (axis_write_req_o.tvalid && axis_write_rsp_i.tready) begin  
            ack_receiving_active_d = 1'b0; // reset when ack-packet is processed
        end
    end

    always_comb begin
        preprocessing_done_d = preprocessing_done_q;
        data_irrelevant_d = data_irrelevant_q;
        if(axis_write_req_o.t.last && axis_write_req_o.tvalid && axis_write_rsp_i.tready) begin
            preprocessing_done_d = 1'b0;
        end
        if(!buffer_empty && !preprocessing_done_q) begin
            preprocessing_done_d = 1'b1;
            data_irrelevant_d = 1'b0;
            if((axis_write_req_o.t.data[7:0] != pjon_device_id_i) && (axis_write_req_o.t.data[7:0] != 255) 
                && !router_mode_i && !ack_receiving_active_q) begin
                data_irrelevant_d = 1'b1;
            end
        end
    end

    `FF(preprocessing_done_q, preprocessing_done_d, '0);
    `FF(data_irrelevant_q, data_irrelevant_d, '0);
    `FF(ack_receiving_active_q, ack_receiving_active_d, 1'b0);
endmodule
