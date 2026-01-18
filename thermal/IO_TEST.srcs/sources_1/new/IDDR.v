`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// IDDR wrapper for Kintex-7
//   clk_out : サンプリングクロック
//   locked  : MMCM などのロック信号（High で有効）
//   IN      : 入力信号（シングルエンド）
//   IN_p    : 立上りエッジでサンプリングされたデータ
//   IN_n    : 立下りエッジでサンプリングされたデータ
//////////////////////////////////////////////////////////////////////////////////

module myIDDR(
    input  wire clk_out,
    input  wire locked,
    input  wire IN,
    output wire IN_p,
    output wire IN_n
    );


    // --- DDR 受信プリミティブ ---
    IDDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"), // posedge→Q1, negedge→Q2
        .SRTYPE("SYNC")
    ) iddr_inst (
        .Q1(IN_p),   // 立上りサンプル出力
        .Q2(IN_n),   // 立下りサンプル出力
        .C (clk_out),
        .CE(locked), // locked=1 のときのみサンプリング
        .D (IN),
        .R (1'b0),
        .S (1'b0)
    );

endmodule
