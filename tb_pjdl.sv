// --------------------------------------------------
// Document:  tb_pjdl.sv
// Project:   PJON_ASIC/PJDL
// Function:  TB for the PJDL-HW implementation
// Autor:     Pius Sieber
// Date:      31.03.2025
// Comments:  -
// --------------------------------------------------

`define TRACE_WAVE

module tb_pjdl #(
    parameter time         ClkPeriod     = 12.5ns,  // 80MHz
    parameter int unsigned RstCycles     = 2        // 1 is not enough to set all the q values correctly
)();
    `include "axi_stream/typedef.svh"
    
    // Axi Stream typedefs
    localparam int unsigned AxisDataWidth       = 8; 
    typedef logic [AxisDataWidth-1:0]     axis_data_t;
    typedef logic                         axis_strb_t;
    typedef logic                         id_t; // id not used
    typedef logic [1:0]                   user_t; // 2 bits
    `AXI_STREAM_TYPEDEF_S_CHAN_T(axis_t_chan_t, axis_data_t, axis_strb_t, axis_strb_t, id_t, id_t, user_t)
    `AXI_STREAM_TYPEDEF_REQ_T(axis_req_t, axis_t_chan_t)
    `AXI_STREAM_TYPEDEF_RSP_T(axis_rsp_t)

    logic clk;
    logic rst_n;

    typedef bit [ 7:0] byte_bt;

    logic pjon_in;
    logic pjon_out;
    logic pjon_en;

    logic [7:0] send_byte;
    logic send_byte_done;

    axis_req_t axis_send_req;
    axis_rsp_t axis_send_rsp;
    axis_req_t axis_send_interconnect_req;
    axis_rsp_t axis_send_interconnect_rsp;
    
    axis_rsp_t axis_receive_rsp;
    axis_req_t axis_receive_req;
    axis_rsp_t axis_receive_interconnect_rsp;
    axis_req_t axis_receive_interconnect_req;

    logic receive_frame_active;
    logic [7:0] received_byte;
    logic received_byte_valid;

    logic start_ack_receiving;


    //////////////
    //  Clocks  //
    //////////////

    clk_rst_gen #(
        .ClkPeriod    ( ClkPeriod ),
        .RstClkCycles ( RstCycles )
    ) i_clk_rst_sys (
        .clk_o  ( clk   ),
        .rst_no ( rst_n )
    );

    //////////////
    //  PJDL    //
    //////////////

    `include "pjdl_tb_tasks.svh";

    ///////////////////
    //  PJDL-Module  //
    ///////////////////

    task automatic pjdl_module_idle();
        axis_send_req.tvalid = 1'b0;
        axis_send_req.t.keep = 1'b1;
        axis_send_req.t.strb = 1'b1;
        axis_send_req.t.user = 2'h0;
    endtask;

    task automatic pjdl_module_send(
        input byte_bt data,
        input logic is_last
    );
        axis_send_req.t.keep = 1'b1;
        axis_send_req.t.strb = 1'b1;
        axis_send_req.t.user = 2'h0;

        axis_send_req.t.data = data;
        axis_send_req.t.last = is_last;
        axis_send_req.tvalid = 1'b1;
        do begin
            @(posedge clk);
            #(1ns);
        end while (axis_send_rsp.tready == 1'b0);
        axis_send_req.tvalid = 1'b0;
    endtask;

    task automatic pjdl_module_send_ack_reqest(
        input byte_bt timeout_length
    );
        axis_send_req.t.data = timeout_length; // number of ack_request sending repetitions bevor timeout
        axis_send_req.t.last = 1'b1;  // ack request is always the last byte
        axis_send_req.t.user = 2'b10; // ack request
        axis_send_req.tvalid = 1'b1;
        do begin
            @(posedge clk);
            #(1ns);
        end while (axis_send_rsp.tready == 1'b0);
        axis_send_req.tvalid = 1'b0;
    endtask

    task automatic pjdl_module_send_ack(
        input byte_bt ack_value
    );
        @(posedge clk);
        #(1ns);
        axis_send_req.t.data = ack_value; // response value
        axis_send_req.t.last = 1'b1;  // ack request is always the last byte
        axis_send_req.t.user = 2'b01; // ack request
        axis_send_req.tvalid = 1'b1;
        do begin
            @(posedge clk);
            #(1ns);
        end while (axis_send_rsp.tready == 1'b0);
        axis_send_req.tvalid = 1'b0;
    endtask

    logic received_last;
    task automatic pjdl_module_receive_frame();
        axis_receive_rsp.tready = 1'b1;
        received_last = 1'b0;
        while(received_last == 1'b0) begin
            @(posedge axis_receive_req.tvalid);
            $display("@%t | [PJON-Test] DUT received data: %h, is_last: %h", $time, 
                axis_receive_req.t.data[7:0], axis_receive_req.t.last);
                received_last = axis_receive_req.t.last;
        end
    endtask

    ////////////
    //  DUT   //
    ////////////
    pjon_addressing #(
        .BufferSize(1),

        .axis_req_t(axis_req_t),
        .axis_rsp_t(axis_rsp_t)
    ) i_pjon_addressing(
        .clk_i                    ( clk                     ),
        .rst_ni                   ( rst_n                   ),

        // send-axi-connection to wrapper
        .axis_read_req_i          ( axis_send_req      ),
        .axis_read_rsp_o          ( axis_send_rsp      ),

        // send-axi-connection from layer 2 module
        .axis_read_req_o          ( axis_send_interconnect_req ),
        .axis_read_rsp_i          ( axis_send_interconnect_rsp ),

        // receive-axi-connection from layer 2 module
        .axis_write_rsp_o         ( axis_receive_interconnect_rsp ),
        .axis_write_req_i         ( axis_receive_interconnect_req ),

        // receive-axi-connection to wrapper
        .axis_write_rsp_i         ( axis_receive_rsp   ),
        .axis_write_req_o         ( axis_receive_req   ),

        .start_ack_receiving_i    ( start_ack_receiving  ), // when ack_receiving is active, 
                                                      // address checking isn't needed

        // PJON Settings
        .pjon_device_id_i         ( 8'b1 ), // PJON Address 1
        .router_mode_i            ( 1'b1 )
    );

    pjdl #(
        .BufferSize(2), // size of the FIFO buffer, minimum size is 1
        .axis_req_t(axis_req_t),
        .axis_rsp_t(axis_rsp_t)
    ) i_pjdl (
        .clk_i                      ( clk                ),
        .rst_ni                     ( rst_n              ),

        // sending
        .axis_read_req_i            ( axis_send_interconnect_req      ),
        .axis_read_rsp_o            ( axis_send_interconnect_rsp      ),
        .sending_in_progress_o      (                    ),
        .start_ack_receiving_o      ( start_ack_receiving),

        // receiving
        .axis_write_rsp_i           ( axis_receive_interconnect_rsp    ),
        .axis_write_req_o           ( axis_receive_interconnect_req    ),
        .receiving_in_progress_o    (                     ),

        // HW interface
        .pjon_i                     ( pjon_in            ),
        .pjon_o                     ( pjon_out           ),
        .pjon_en_o                  ( pjon_en            ),

        .pjdl_spec_preamble_i       ( 20'h0              ),
        .pjdl_spec_pad_i            ( 14'd8800           ),
        .pjdl_spec_data_i           ( 12'd3520           ),
        .pjdl_spec_acceptance_i     ( 13'd4480           )
    );

    /////////////////
    //  Testbench  //
    /////////////////

    byte_bt ack_receive_value;
    logic tb_receive_ack;

    // Testing sequence
    initial begin
        $timeformat(-9, 0, "ns", 12); // 1: scale (ns=-9), 2: decimals, 3: suffix, 4: print-field width
        // configure VCD dump
        `ifdef TRACE_WAVE
            $dumpfile("pjdl.vcd");
            $dumpvars(1,i_pjdl);
        `endif

        
        // wait for reset
        #ClkPeriod;
        tb_receive_ack = 1'b0;

        $display("@%t | [PJON-Test] Start simulation", $time);

        pjdl_module_idle();
        repeat(50) @(posedge clk);
        #(5ns)

        $display("@%t | [PJON-Test] Preparing Data to Receive over PJDL from DUT... ", $time);
        pjdl_module_send(8'h01, 1'b0);
        pjdl_module_send(8'h02, 1'b0);
        pjdl_module_send(8'h03, 1'b0);
        pjdl_module_send(8'hF0, 1'b1);
        
        #(5ms);

        // Next frame
        pjdl_module_send(8'h05, 1'b0);
        pjdl_module_send(8'h06, 1'b0);
        pjdl_module_send(8'h07, 1'b0);
        pjdl_module_send(8'hF0, 1'b1);
        pjdl_module_send_ack_reqest(8'h09); // 9 repetition of maximum timeout for ack request

        #(10ms);

        $display("@%t | [PJON-Test] send packet over PJDL to DUT...", $time);
        pjdl_send_preamble();
        pjdl_frame_init(1);
        pjdl_send_byte(8'h01, 1); // Receiver-ID
        pjdl_send_byte(8'h00, 1); // HEADER-Bitmap
        pjdl_send_byte(8'h06, 1); // Length
        pjdl_send_byte(8'h54, 1); // CRC
        pjdl_send_byte(8'h41, 1); // Data: "A"
        pjdl_send_byte(8'h5A, 1); // CRC

        #(10ms);

        pjdl_send_preamble();
        pjdl_frame_init(1);
        pjdl_send_byte(8'h02, 1);
        pjdl_send_byte(8'h02, 1);
        pjdl_send_byte(8'h03, 1);
        pjdl_send_byte(8'h04, 1);
        #(0.2ms);
        tb_receive_ack = 1'b1;
        pjdl_send_ack_request(); // ToDo: check if this is too late

        // finish simulation
        #(10ms);
        repeat(50) @(posedge clk);
        `ifdef TRACE_WAVE
        $dumpflush;
        `endif
        $finish();
    end

    // Receiving directly over PJDL what the DUT sent
    initial begin
        pjdl_receive_frame(receive_value, 1);
        $display("@%t | [PJON-Test] TB received frame has ended, trying to receive second frame...", $time);
        pjdl_receive_frame(receive_value, 1);
        #(1ms);
        @(negedge pjon_out);
        $display("@%t | [PJON-Test] TB received frame has ended, send ack...", $time);
        pjdl_send_byte(8'h01, 1); // ACK
    end

    // Receiving over Axi-stream what the DUT received over PJDL
    initial begin
        @(posedge rst_n);

        axis_receive_rsp.tready = 1'b1;
        /*while(1'b1) begin
            @(posedge receive_frame_data.tvalid);
            $display("@%t | [PJON-Test] DUT received data: %h, is_last: %h", $time, 
                receive_frame_data.tdata[7:0], receive_frame_data.tlast);
        end*/
        pjdl_module_receive_frame(); // ack 
        pjdl_module_receive_frame();
        $display("@%t | [PJON-Test] DUT first frame has ended, receiving second...", $time);
        pjdl_module_receive_frame();
        #(1ms);
        $display("@%t | [PJON-Test] DUT received frame has ended, send ack...", $time);
        pjdl_module_send_ack(8'h05);
    end

    initial begin
        #(1ms);
        @(posedge tb_receive_ack);
        pjdl_receive_ack(.receive_value(ack_receive_value));
    end

endmodule
