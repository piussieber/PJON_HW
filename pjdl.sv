// --------------------------------------------------
// Document:  pjdl.sv
// Project:   PJON_ASIC/PJDL
// Function:  HW implementation of the PJDL strategy of PJON
// Autor:     Pius Sieber
// Date:      31.03.2025
// Comments:  -
// --------------------------------------------------

module pjdl #(
    parameter int BufferSize = 2, // size of the FIFO buffer, minimum size is 1

    parameter type axis_req_t  = logic,
    parameter type axis_rsp_t  = logic
)(
    input   logic clk_i,
    input   logic rst_ni,

    // send-axi-connection to layer 3 or wrapper
    input axis_req_t axis_read_req_i,
    output axis_rsp_t axis_read_rsp_o,
    
    // receive-axi-connection to layer 3 or wrapper
    input axis_rsp_t axis_write_rsp_i,
    output axis_req_t axis_write_req_o,

    output logic sending_in_progress_o,
    output logic receiving_in_progress_o,
    output logic start_ack_receiving_o,

    // HW interface
    input   logic pjon_i,
    output  logic pjon_o,
    output  logic pjon_en_o,

    // PJDL specification (mode dependent)
    input   logic [19:0] pjdl_spec_preamble_i,
    input   logic [13:0] pjdl_spec_pad_i,
    input   logic [11:0] pjdl_spec_data_i,
    input   logic [12:0] pjdl_spec_acceptance_i // minimum length of a pad to be accepted 
);

    logic start_ack_receiving;

    assign start_ack_receiving_o = start_ack_receiving;

    pjdl_send #(
        .BufferSize(BufferSize),

        .axis_req_t(axis_req_t),
        .axis_rsp_t(axis_rsp_t)
    ) i_pjdl_send (
        .clk_i                  ( clk_i                    ),
        .rst_ni                 ( rst_ni                   ),
        .enable_i               ( !receiving_in_progress_o  ), // disable sending when receiving 
                                                               // is in progress

        // Axi interface
        .axis_read_req_i        ( axis_read_req_i),
        .axis_read_rsp_o        ( axis_read_rsp_o),

        .sending_in_progress_o  ( sending_in_progress_o ),
        .start_ack_receiving_o  ( start_ack_receiving   ),

        // HW interface
        .pjon_i                 ( pjon_i      ),
        .pjon_o                 ( pjon_o      ),
        .pjon_en_o              ( pjon_en_o   ),

        // PJDL specification (mode dependent)
        .pjdl_spec_preamble_i   ( pjdl_spec_preamble_i ),
        .pjdl_spec_pad_i        ( pjdl_spec_pad_i      ),
        .pjdl_spec_data_i       ( pjdl_spec_data_i     )
    );

    pjdl_receive #(
        .BufferSize(BufferSize),
        
        .axis_req_t(axis_req_t),
        .axis_rsp_t(axis_rsp_t)
    ) i_pjdl_receive(
        .clk_i                  ( clk_i                  ),
        .rst_ni                 ( rst_ni                 ),
        .enable_i               ( !sending_in_progress_o ), // disable receiving when sending 
                                                            // is in progress

        // Axi interface
        .axis_write_rsp_i        ( axis_write_rsp_i),
        .axis_write_req_o        ( axis_write_req_o),

        .receiving_in_progress_o ( receiving_in_progress_o ),
        .start_ack_receiving_i   ( start_ack_receiving     ),

        // HW interface
        .pjon_i                 ( pjon_i   ),

        // PJDL specification (mode dependent)
        .pjdl_spec_preamble_i   ( pjdl_spec_preamble_i      ),
        .pjdl_spec_pad_i        ( pjdl_spec_pad_i           ),
        .pjdl_spec_data_i       ( pjdl_spec_data_i          ),
        .pjdl_spec_acceptance_i ( pjdl_spec_acceptance_i    )
    );

endmodule