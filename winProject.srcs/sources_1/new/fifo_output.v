`timescale 1ns / 1ps

module fifo_output(
    // 上位から受け取る信号は必ずポートにする（未駆動を防ぐ）
    input  wire        OSC,
    input  wire        clk_out,
    input  wire        locked,
    input  wire        IN1,
    input  wire        IN2,
    input  wire        IN3,
    input  wire        IN4,
    input  wire        IN5,
    input  wire        IN6,
    output wire [7:0]  dout_8bit_ext,
    output wire        valid_ext,
    input  wire        clk125M,
    input  wire        rd_rq,
    input  wire        SW
);

    wire [55:0] dout1, dout2, dout3, dout4, dout5, dout6;
    wire        valid1, valid2, valid3, valid4, valid5, valid6;
    wire        empty1, empty2, empty3, empty4, empty5, empty6;

    reg empty1_ext, empty2_ext, empty3_ext, empty4_ext, empty5_ext, empty6_ext;

    reg [2:0] state;

    // 64bit パケット {ID(8), DATA(56)}
    reg  [63:0] din;
    reg         wr_en;

    // FIFO 1（信号名の衝突/多重ドライブを回避）
    wire [7:0] dout_8bit;
    wire       valid;
    wire       empty;
    wire       full1;
    wire       rd_en = ~empty;

    // --- パラメータ ---
    localparam integer LATENCY  = 0;  // 要求パルスから valid まで最短
    localparam integer MAX_WAIT = 5;  // 要求パルスから最大待ち

    reg        waiting;      // valid待ち中
    reg [2:0]  wait_cnt;     // 要求パルス後の経過クロック数 (1..MAX_WAIT)
    reg        req_pulsed;   // このstateで要求パルスを既に出したか（=1回だけ）

    // =========================
    // pkt_id 生成（要求仕様どおり）
    //   SW=1: BoardID=111, 下位5bit={00,state}
    //   SW=0: BoardID=000, 下位5bit=state+6 を5bitで
    // =========================
    wire [2:0] boardID_sel = SW ? 3'b000 : 3'b111;
    wire [4:0] ch_id       = SW ? {2'b00, state} : ({2'b00, state} + 5'd6);
    wire [7:0] pkt_id      = {boardID_sel, ch_id};

    wire sel_valid =
        (state==3'd1) ? valid1 :
        (state==3'd2) ? valid2 :
        (state==3'd3) ? valid3 :
        (state==3'd4) ? valid4 :
        (state==3'd5) ? valid5 :
        (state==3'd6) ? valid6 : 1'b0;

    wire [55:0] sel_dout  =
        (state==3'd1) ? dout1 :
        (state==3'd2) ? dout2 :
        (state==3'd3) ? dout3 :
        (state==3'd4) ? dout4 :
        (state==3'd5) ? dout5 :
        (state==3'd6) ? dout6 : 56'd0;

    task automatic advance_state;
    begin
        if (state == 3'd6) state <= 3'd1;
        else               state <= state + 3'd1;
    end
    endtask

    always @(posedge OSC) begin
      if (!locked) begin
        state      <= 3'd1;
        waiting    <= 1'b0;
        wait_cnt   <= 3'd0;
        req_pulsed <= 1'b0;

        din   <= 64'd0;
        wr_en <= 1'b0;

        empty1_ext <= 1'b0; empty2_ext <= 1'b0; empty3_ext <= 1'b0;
        empty4_ext <= 1'b0; empty5_ext <= 1'b0; empty6_ext <= 1'b0;

      end else begin
        // デフォルト
        wr_en <= 1'b0;

        // empty_ext は基本0（パルス時だけ1）
        empty1_ext <= 1'b0; empty2_ext <= 1'b0; empty3_ext <= 1'b0;
        empty4_ext <= 1'b0; empty5_ext <= 1'b0; empty6_ext <= 1'b0;

        if (!waiting) begin
          // WAITに入ってない＝このstateの処理開始
          if (!req_pulsed) begin
            // 1クロックだけ要求パルス
            case (state)
              3'd1: empty1_ext <= 1'b1;
              3'd2: empty2_ext <= 1'b1;
              3'd3: empty3_ext <= 1'b1;
              3'd4: empty4_ext <= 1'b1;
              3'd5: empty5_ext <= 1'b1;
              3'd6: empty6_ext <= 1'b1;
              default: ;
            endcase

            // 次クロックから待つ
            waiting    <= 1'b1;
            req_pulsed <= 1'b1;
            wait_cnt   <= 3'd1;  // 「パルスを出した次のクロック」を1と数える
          end
        end else begin
          // valid待ち中：カウンタ進行（最大MAX_WAITまで）
          if (wait_cnt < MAX_WAIT[2:0])
            wait_cnt <= wait_cnt + 3'd1;

          // 最短LATENCY未満はvalid無視
          if (wait_cnt >= LATENCY[2:0] && sel_valid) begin
            // 取り込み
            din   <= {pkt_id, sel_dout};
            wr_en <= 1'b1;

            // 次stateへ
            waiting    <= 1'b0;
            wait_cnt   <= 3'd0;
            req_pulsed <= 1'b0;
            advance_state();

          end else if (wait_cnt == MAX_WAIT[2:0]) begin
            // タイムアウト：書かずに次stateへ
            waiting    <= 1'b0;
            wait_cnt   <= 3'd0;
            req_pulsed <= 1'b0;
            advance_state();
          end
        end
      end
    end

    // all_Data インスタンス（変更なし）
    all_Data data1(
        .clk_out (clk_out), .locked(locked), .IN(IN1), .OSC(OSC),
        .dout(dout1), .valid(valid1), .empty(empty1), .empty_ext(empty1_ext)
    );
    all_Data data2(
        .clk_out (clk_out), .locked(locked), .IN(IN2), .OSC(OSC),
        .dout(dout2), .valid(valid2), .empty(empty2), .empty_ext(empty2_ext)
    );
    all_Data data3(
        .clk_out (clk_out), .locked(locked), .IN(IN3), .OSC(OSC),
        .dout(dout3), .valid(valid3), .empty(empty3), .empty_ext(empty3_ext)
    );
    all_Data data4(
        .clk_out (clk_out), .locked(locked), .IN(IN4), .OSC(OSC),
        .dout(dout4), .valid(valid4), .empty(empty4), .empty_ext(empty4_ext)
    );
    all_Data data5(
        .clk_out (clk_out), .locked(locked), .IN(IN5), .OSC(OSC),
        .dout(dout5), .valid(valid5), .empty(empty5), .empty_ext(empty5_ext)
    );
    all_Data data6(
        .clk_out (clk_out), .locked(locked), .IN(IN6), .OSC(OSC),
        .dout(dout6), .valid(valid6), .empty(empty6), .empty_ext(empty6_ext)
    );

    fifo_generator_1 all_ch_data (
      .clk  (OSC),
      .din  (din),
      .wr_en(wr_en),
      .rd_en(rd_en),
      .dout (dout_8bit),   // [7:0]
      .full (full1),
      .empty(empty),
      .valid(valid)
    );

    // FIFO 2
    wire       empty_ext;
    wire       full2;
    wire       rd_en_ext = ~empty_ext && rd_rq;
    wire       srst      = 1'b0;   // 未使用なので0固定
    wire       wr_rst_busy;
    wire       rd_rst_busy;

    fifo_generator_2 fifo_125M (
        .clk   (OSC),
        .srst  (srst),
        .din   (dout_8bit),
        .wr_en (valid),

        .rd_en (rd_en_ext),
        .dout  (dout_8bit_ext),
        .full  (full2),
        .empty (empty_ext),
        .valid (valid_ext)
    );

    ila_0 u_ila0(
        .clk(OSC),
        .probe0({valid1,valid2,valid3,valid4,valid5,valid6}),
        .probe1(din),
        .probe2(dout1),
        .probe3(wr_en),
        .probe4(state),
        .probe5({IN1,IN2,IN3,IN4,IN5,IN6}),
        .probe6(dout_8bit),
        .probe7(dout_8bit_ext),
        .probe8(valid),
        .probe9(rd_en_ext),
        .probe10(valid_ext),
        .probe11(clk_out)
    );

endmodule
