`timescale 1ns / 1ps
`default_nettype none

module packet_builder(
    input  wire        OSC,            // 125 MHz
    input  wire [7:0]  dout_8bit_ext,  // 外部FIFOから
    input  wire        valid,          // 外部FIFO valid
    output reg         rd_rq,          // 外部FIFO read request

    // SiTCP に渡す "FIFO 出力"
    output wire [7:0]  packet2,        // 最終送信データ
    output wire        tx_we2,         // 最終送信書込パルス (valid)

    output reg         packet_done,    // 1イベント終了
    input  wire        TCP_TX_FULL     // SiTCP FULL
);

    //==== 状態定義 ==========================================================
    localparam S_IDLE    = 3'd0;
    localparam S_COLLECT = 3'd1;
    localparam S_HEADER  = 3'd2;
    localparam S_PAYLOAD = 3'd3;
    localparam S_FOOTER  = 3'd4;

    reg [2:0] state = S_IDLE;
    reg [2:0] byte_cnt = 3'd0;
    reg [3:0] send_cnt = 4'd0;
    reg [7:0] buffer [7:0];

    reg        tx_we;      // FIFO write pulse
    reg [7:0]  packet;     // FIFO write data

    integer i;

    //======================================================================
    // 送信 FSM
    //======================================================================
    always @(posedge OSC) begin
        // default
        tx_we       <= 1'b0;
        packet_done <= 1'b0;
        rd_rq       <= 1'b0;

        case (state)

            //----- 初期状態 ------------------------------------------------
            S_IDLE: begin
                byte_cnt <= 0;
                rd_rq <= 1'b1;
                if (valid) begin
                    buffer[0] <= dout_8bit_ext;
                    byte_cnt  <= 1;
                    state     <= S_COLLECT;
                end
            end

            //----- 8 バイト収集 -------------------------------------------
            S_COLLECT: begin
                rd_rq <= 1'b1;
                if (valid) begin
                    buffer[byte_cnt] <= dout_8bit_ext;
                    byte_cnt <= byte_cnt + 1;

                    if (byte_cnt == 3'd7) begin
                        rd_rq    <= 1'b0;
                        send_cnt <= 0;
                        state    <= S_HEADER;
                    end
                end
            end

            //----- ヘッダ送信 ----------------------------------------------
            S_HEADER: begin
                tx_we <= 1'b1;
                case (send_cnt)
                    0: packet <= 8'hAA;
                    1: packet <= 8'h55;
                endcase

                send_cnt <= send_cnt + 1;
                if (send_cnt == 1) begin
                    send_cnt <= 0;
                    state <= S_PAYLOAD;
                end
            end

            //----- ペイロード送信 -----------------------------------------
            S_PAYLOAD: begin
                tx_we  <= 1'b1;
                packet <= buffer[send_cnt];
                send_cnt <= send_cnt + 1;

                if (send_cnt == 7) begin
                    send_cnt <= 0;
                    state    <= S_FOOTER;
                end
            end

            //----- フッタ送信 ----------------------------------------------
            S_FOOTER: begin
                tx_we <= 1'b1;
                case (send_cnt)
                    0: packet <= 8'h55;
                    1: packet <= 8'hAA;
                endcase

                send_cnt <= send_cnt + 1;
                if (send_cnt == 1) begin
                    send_cnt <= 0;
                    packet_done <= 1'b1;
                    state <= S_IDLE;
                end
            end
        endcase
    end

    //======================================================================
    // 1 段 FIFO（FSM と SiTCP の間）
    //======================================================================

    wire fifo_full;
    wire fifo_empty;

    // FSM の出力を FIFO に書き込む
    wire wr_en = tx_we;

    // FULL=1 のときは読み出し停止 → SiTCP 側が停止する
    wire rd_en = ~TCP_TX_FULL;

    fifo_generator_3 txfifo (
        .clk(OSC),
        .srst(1'b0),
        .din(packet),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .dout(packet2),
        .full(fifo_full),
        .empty(fifo_empty),
        .valid(tx_we2)      // 最終 tx_we2
    );

endmodule

`default_nettype wire
