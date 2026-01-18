`timescale 1ns / 1ps

module TDC(
    input  wire        clk_out,
    input  wire        locked,
    input  wire        IN,
    output reg  [55:0] counter2,
    output reg         wr_en
);

    // 外部
    wire        IN_p;
    wire        IN_n;
    wire [54:0] counter;

    myIDDR myiddr(
        .clk_out(clk_out),
        .locked (locked),
        .IN     (IN),
        .IN_p   (IN_p),
        .IN_n   (IN_n)
    );

    COUNT count(
        .clk_out (clk_out),
        .locked  (locked),
        .counter (counter)
    );

    // PN: IN_p=1なら常に0、IN_p=0かつIN_n=1なら1、その他0
    reg  PN;
    wire pn_next = (~IN_p & IN_n);  // 仕様をそのまま式にした形

    // IN_n 立上り検出（1クロック・パルスを wr_en に出力）
    reg in_n_d;

    always @(posedge clk_out) begin
        if (!locked) begin
            PN       <= 1'b0;
            counter2 <= 56'd0;
            in_n_d   <= 1'b0;
            wr_en    <= 1'b0;
        end else begin
            // PN 更新
            PN <= pn_next;

            // counter2 更新：IN_p/IN_nのどちらかが1のときだけ {counter, pn_next}、両方0なら0
            if (IN_p | IN_n)
                counter2 <= {1'b0 , counter};  // 63bitカウンタ + 1bit PN = 64bit
            else
                counter2 <= 56'd0;

            // wr_en：IN_nの立上りで1クロックだけ1
            wr_en  <= IN_n & ~in_n_d;
            in_n_d <= IN_n;
        end
    end

endmodule
