// --------------------------------------------------
// Document:  pjdl_tb_tasks.sv
// Project:   PJON_ASIC/PJDL
// Function:  Task and constants collection for PJDL testbenches
// Autor:     Pius Sieber
// Date:      24.04.2025
// Comments:  -
// --------------------------------------------------

// Specification:
localparam realtime PJDL_TIMING_SPEC[1:4][0:3][0:2] = '{
//  '-' is negative tolerance, '+' is positive tolerance 
//  {  Preamble bit         ,   Pad bit         ,   Data bit       ,  Keep busy bit     }
//  {{  time ,       - ,  + }, { time,   - ,   + }, {time,   - ,   + }, {time  ,   - ,   + }}  
    // Mode 1 (1.97 kB/s)
    {{11000us, -11000us, 0us}, {110us, -5us, 17us}, {44us, -5us, 17us}, {11us  , -5us, 10us}},
    // Mode 2 (2.21 kB/s)  
    {{ 9200us,  -9200us, 0us}, { 92us, -4us, 16us}, {40us, -4us, 16us}, {10us  , -5us, 10us}},
    // Mode 3 (3.10 kB/s)
    {{ 7000us,  -7000us, 0us}, { 70us, -3us, 11us}, {28us, -3us, 11us}, { 7us  , -3us, 10us}}, 
    // Mode 4 (3.34 kB/s)
    {{ 6500us,  -6500us, 0us}, { 65us, -3us, 10us}, {26us, -3us, 10us}, { 6.5us, -3us, 10us}}  
};

localparam int unsigned PJDL_PREAMB   = 0;  // PJDL Preamble bit
localparam int unsigned PJDL_PAD      = 1;  // PJDL Pad bit
localparam int unsigned PJDL_DATA     = 2;  // PJDL Data bit
localparam int unsigned PJDL_BUSY_BIT = 3;  // PJDL Keep busy bit
localparam int unsigned PJDL_DEF_TIME = 0;  // PJDL Default time
localparam int unsigned PJDL_NEG_TOL  = 1;  // PJDL Negative tolerance
localparam int unsigned PJDL_POS_TOL  = 2;  // PJDL Positive tolerance

realtime pad_offset, data_offset;

// tol_offset specifies the offset from the maximum tolerances to be tested
task automatic pjdl_send_byte(
    input byte_bt send_value,
    input int unsigned mode = 1, // communication speed mode
    input logic at_limit = 1, // 0 = test at specification, 1 = test at limit
    input int unsigned limit = PJDL_NEG_TOL, // which limit to test
    input realtime tol_offset = 2us // how far from the actual limit (in the direction of the specified value))
);
    pad_offset = (!at_limit ? ((limit==PJDL_NEG_TOL) ? PJDL_TIMING_SPEC[mode][PJDL_PAD][limit]
        + tol_offset : PJDL_TIMING_SPEC[mode][PJDL_PAD][limit] - tol_offset) : 0);
    data_offset = (!at_limit ? ((limit==PJDL_NEG_TOL) ? PJDL_TIMING_SPEC[mode][PJDL_DATA][limit]
        + tol_offset : PJDL_TIMING_SPEC[mode][PJDL_PAD][limit] - tol_offset) : 0);
    //----------------------- Sync
    pjon_in = 1'b1; // 1
    #(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + pad_offset);
    pjon_in = 1'b0; // 0
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    //------------------------ Byte
    pjon_in = send_value[0]; 
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[1];
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[2]; 
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[3]; 
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[4]; 
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[5];
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[6];
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    pjon_in = send_value[7];
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
endtask

task automatic pjdl_send_preamble(
    input preamble_time = 110us,
);
    pjon_in = 1'b1;
    #preamble_time;
endtask

task automatic pjdl_frame_init(
    input int unsigned mode = 1,
    input logic at_limit = 1,
    input int unsigned limit = PJDL_NEG_TOL,
    input realtime tol_offset = 2us
);
    pad_offset = (at_limit ? ((limit==PJDL_NEG_TOL) ? PJDL_TIMING_SPEC[mode][PJDL_PAD][limit]
        + tol_offset : PJDL_TIMING_SPEC[mode][PJDL_PAD][limit] - tol_offset) : 0);
    data_offset = (at_limit ? ((limit==PJDL_NEG_TOL) ? PJDL_TIMING_SPEC[mode][PJDL_DATA][limit]
        + tol_offset : PJDL_TIMING_SPEC[mode][PJDL_PAD][limit] - tol_offset) : 0);
    //----------------------- Sync
    pjon_in = 1'b1; // 1
    #(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + pad_offset);
    pjon_in = 1'b0; // 0
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    //----------------------- Sync
    pjon_in = 1'b1; // 1
    #(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + pad_offset);
    pjon_in = 1'b0; // 0
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
    //----------------------- Sync
    pjon_in = 1'b1; // 1
    #(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + pad_offset);
    pjon_in = 1'b0; // 0
    #(PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME] + data_offset);
endtask

realtime signal_end_time;
logic pjdl_stayed_low;
task automatic pjdl_send_ack_request(
    input int unsigned mode = 1
);
    //*********************************** Busy Bits
    pjon_in = 1'b0; // 0
    pjdl_stayed_low = 1'b1;
    #(PJDL_TIMING_SPEC[mode][PJDL_BUSY_BIT][PJDL_DEF_TIME]);
    while ((!pjon_out) && pjdl_stayed_low) begin
        pjon_in = 1'b0; // 0
        signal_end_time = $realtime + (2*PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]);
        while($realtime<signal_end_time) begin
            #(5us);
            //$display("@%t | [PJON-Test] waiting", $time);
            if(pjon_out == 1'b1) begin
                pjdl_stayed_low = 1'b0;
                break;
            end
        end
        if(pjdl_stayed_low == 1'b0) begin
            break;
        end
        pjon_in = 1'b1; // 1
        #(PJDL_TIMING_SPEC[mode][PJDL_BUSY_BIT][PJDL_DEF_TIME]);
    end
    $display("@%t | [PJON-Test] ack request ended", $time);
endtask

task automatic pjdl_receive_ack(
    input int unsigned mode = 1,
    output byte_bt receive_value
);
    // *********************************** Data-Sync
    //@(negedge pjon_out);
    @(posedge pjon_out);
    signal_start = $realtime;
    @(negedge pjon_out);
    signal_time = $realtime - signal_start;
    assert(signal_time >
        (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL])) 
        else $display("@%t | [PJON-Test] Output-mismatch: ACK-Sync-Pad is too short", $time);
    assert(signal_time < 
        (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL])) 
        else $display("@%t | [PJON-Test] Output-mismatch: ACK-Sync-Pad is too long", $time);

    // *********************************** Data
    #(2*half_bit_time); //negtive sync-bit
    #half_bit_time;
    receive_value[0] = pjon_out;
    #(2*half_bit_time);
    receive_value[1] = pjon_out;
    #(2*half_bit_time);
    receive_value[2] = pjon_out;
    #(2*half_bit_time);
    receive_value[3] = pjon_out;
    #(2*half_bit_time);
    receive_value[4] = pjon_out;
    #(2*half_bit_time);
    receive_value[5] = pjon_out;
    #(2*half_bit_time);
    receive_value[6] = pjon_out;
    #(2*half_bit_time);
    receive_value[7] = pjon_out;

    //signal_time = $realtime - signal_start;
    $display("@%t | [PJON-Test] TB received ack: %h", $time, receive_value);

    #(2*half_bit_time);
    //#(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]);
    //#(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL]);
endtask

realtime half_bit_time, signal_start, signal_time;
byte_bt receive_value;

task automatic pjdl_receive_frame(
    output byte_bt receive_value,
    input int unsigned mode = 1
);
    // *********************************** Preamble & Sync 1
    @(posedge pjon_out);
    signal_start = $realtime;

    @(negedge pjon_out);
    signal_time = $realtime - signal_start;
    signal_start = $realtime;
    assert(signal_time >
        (PJDL_TIMING_SPEC[mode][PJDL_PREAMB][PJDL_DEF_TIME]+ PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DEF_TIME][PJDL_NEG_TOL] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Preamble and first Sync-Pad is too short", $time);
    assert(signal_time < 
        (PJDL_TIMING_SPEC[mode][PJDL_PREAMB][PJDL_DEF_TIME] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DEF_TIME][PJDL_POS_TOL] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Preamble and first Sync-Pad is too long", $time);

    @(posedge pjon_out);
    signal_time = $realtime - signal_start;
    signal_start = $realtime;
    assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit1 is too short", $time);
    assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit1 is too long", $time);

    // *********************************** Sync 2
    @(negedge pjon_out);
    signal_time = $realtime - signal_start;
    signal_start = $realtime;
    assert(signal_time >
        (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL])) 
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad2 is too short", $time);
    assert(signal_time < 
        (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL])) 
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad2 is too long", $time);

    @(posedge pjon_out);
    signal_time = $realtime - signal_start;
    half_bit_time = signal_time / 2;
    signal_start = $realtime;
    assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit2 is too short", $time);
    assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit2 is too long", $time);

    // *********************************** Sync 3
    @(negedge pjon_out);
    signal_time = $realtime - signal_start;
    signal_start = $realtime;
    assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad3 is too short", $time);
    assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad3 is too long", $time);

    @(posedge pjon_out);
    signal_time = $realtime - signal_start;
    half_bit_time = signal_time / 2;
    signal_start = $realtime;
    assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit3 is too short", $time);
    assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Bit3 is too long", $time);

    // *********************************** Data-Sync and Data
    @(negedge pjon_out);
    signal_time = $realtime - signal_start;
    signal_start = $realtime;
    assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad3 is too short", $time);
    assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
        + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL]))
        else $display("@%t | [PJON-Test] Output-mismatch: Sync-Pad3 is too long", $time);

    // *********************************** Data
    do begin
        if(pjon_out == 1'b1) begin // only valid after first byte was received
            @(negedge pjon_out);
            signal_time = $realtime - signal_start;
            signal_start = $realtime;
            assert(signal_time > (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME] 
                + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_NEG_TOL])
                + 9*PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
                + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_NEG_TOL])
                else $display("@%t | [PJON-Test] Output-mismatch: Data-part is too short", $time);
            assert(signal_time < (PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]
                + PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL])
                + 9*PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_DEF_TIME]
                + PJDL_TIMING_SPEC[mode][PJDL_DATA][PJDL_POS_TOL])
                else $display("@%t | [PJON-Test] Output-mismatch: Data-part is too long", $time);
            // ToDo: improve this assertion
        end
        #(2*half_bit_time); //sync-bit
        #half_bit_time;
        receive_value[0] = pjon_out;
        #(2*half_bit_time);
        receive_value[1] = pjon_out;
        #(2*half_bit_time);
        receive_value[2] = pjon_out;
        #(2*half_bit_time);
        receive_value[3] = pjon_out;
        #(2*half_bit_time);
        receive_value[4] = pjon_out;
        #(2*half_bit_time);
        receive_value[5] = pjon_out;
        #(2*half_bit_time);
        receive_value[6] = pjon_out;
        #(2*half_bit_time);
        receive_value[7] = pjon_out;

        //signal_time = $realtime - signal_start;
        $display("@%t | [PJON-Test] TB received data: %h", $time, receive_value);

        #(2*half_bit_time);
        //#(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_DEF_TIME]);
        //#(PJDL_TIMING_SPEC[mode][PJDL_PAD][PJDL_POS_TOL]);
    end while (pjon_out == 1'b1);
endtask