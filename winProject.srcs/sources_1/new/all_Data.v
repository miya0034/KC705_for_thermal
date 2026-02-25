`timescale 1ns / 1ps

module all_Data(
    input  wire        clk_out,
    input  wire        locked,
    input  wire        IN,
    input  wire        OSC,
    input  wire        empty_ext,   // 上位（fifo_output）から渡される拡張empty信号
    output wire [55:0] dout,
    output wire        valid,
    output wire        empty
);

    // === TDC 出力 ===
    wire [55:0] counter3;
    wire        wr_en_raw;   // TDCが出す書き要求(1クロックパルス想定)

    TDC tdc (
        .clk_out (clk_out),
        .locked  (locked),
        .IN      (IN),
        .counter2(counter3),
        .wr_en   (wr_en_raw)
    );

    // FIFO 信号
    wire full;
    wire sbiterr, dbiterr;
    wire wr_rst_busy, rd_rst_busy;

    // 書き込み側: fullでガード
    wire wr_en = wr_en_raw & ~full;

    // 読み出し側: 空でなく、かつempty_extが1の時読み進める
    wire rd_en = ~empty && empty_ext;

    // FIFO
    fifo_generator_0 fifo_IN1 (
        .rst         (!locked),   // active-High reset
        .wr_clk      (clk_out),   // write clock 250 MHz
        .rd_clk      (OSC),       // read  clock 200 MHz
        .din         (counter3),  // [55:0]
        .wr_en       (wr_en),
        .rd_en       (rd_en),
        .dout        (dout),      // [55:0]
        .full        (full),
        .empty       (empty),
        .valid       (valid),
        .sbiterr     (sbiterr),
        .dbiterr     (dbiterr),
        .wr_rst_busy (wr_rst_busy),
        .rd_rst_busy (rd_rst_busy)
    );

endmodule
