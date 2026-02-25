module FIFO1(
    input  wire        clk_out,   // 書き側クロック
    input  wire        rd_clk,    // 読み側クロック
    input  wire        locked,    // 安定指示
    input  wire        IN,        // 外部イベント(非同期想定)

    input  wire        rd_en,         // 読み要求
    output wire [63:0] fifo_dout,     // 読みデータ
    output wire        fifo_empty,    // 空フラグ
    output wire        fifo_data_valid// データ有効
);
    // パラメータ：TDC処理に起因する「IN→counter3」までの遅延クロック数
    parameter integer L = 1;

    // 1) TDC本体（counter3を生成）
    wire [63:0] counter3;
    TDC tdc(
        .clk_out  (clk_out),
        .locked   (locked),
        .IN       (IN),
        .counter2 (counter3)
    );

    // 2) INをclk_outに同期化して立上りパルス化
    reg in_ff1, in_ff2;
    always @(posedge clk_out) begin
        if (!locked) begin
            in_ff1 <= 1'b0;
            in_ff2 <= 1'b0;
        end else begin
            in_ff1 <= IN;          // 1段目
            in_ff2 <= in_ff1;      // 2段目
        end
    end
    wire in_rise =  in_ff1 & ~in_ff2;  // 1クロック幅

    // 3) イベントをLクロック遅延
    reg [L-1:0] ev_pipe;  // L>=1とする
    always @(posedge clk_out) begin
        if (!locked) ev_pipe <= {L{1'b0}};
        else         ev_pipe <= {ev_pipe[L-2:0], in_rise};
    end
    wire wr_req = ev_pipe[L-1];        // ＝ INのLクロック後

    // 4) 書込みデータを遅延後の同一クロックでラッチ（安全）
    reg [63:0] din_reg;
    always @(posedge clk_out) begin
        if (!locked)        din_reg <= 64'd0;
        else if (wr_req)    din_reg <= counter3;  // t+Lクロック時点のcounter3を捕捉
    end

    // 5) 非同期FIFO（書: clk_out、読: rd_clk）
    wire fifo_full;
    xpm_fifo_async #(
      .WRITE_DATA_WIDTH   (64),
      .READ_DATA_WIDTH    (64),
      .FIFO_WRITE_DEPTH   (64),        // 深さは必要最小で可。余裕なら128
      .READ_LATENCY       (1),
      .CDC_SYNC_STAGES    (2),
      .FIFO_MEMORY_TYPE   ("auto"),
      .ECC_MODE           ("no_ecc"),
      .WR_DATA_COUNT_WIDTH(7),
      .RD_DATA_COUNT_WIDTH(7),
      .PROG_FULL_THRESH   (56),
      .PROG_EMPTY_THRESH  (8)
    ) u_fifo_async (
      .rst          (~locked),

      // write domain
      .wr_clk       (clk_out),
      .wr_en        (wr_req & ~fifo_full),
      .din          (din_reg),
      .full         (fifo_full),
      .prog_full    (),
      .wr_data_count(),

      // read domain
      .rd_clk       (rd_clk),
      .rd_en        (rd_en & ~fifo_empty),
      .dout         (fifo_dout),
      .data_valid   (fifo_data_valid),
      .empty        (fifo_empty),
      .prog_empty   (),
      .rd_data_count()
    );
endmodule
