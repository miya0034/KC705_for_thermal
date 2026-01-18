`timescale 1ns / 1ps

module fifo_output(
    // 上位から受け取る信号は必ずポートにする（未駆動を防ぐ）
    input  wire        OSC,
    input  wire        clk_out,
    input  wire        locked,
    input  wire        IN1,
    input wire         IN2,
    input  wire        IN3,
    input  wire        IN4,
    input  wire        IN5,
    input  wire        IN6,
    output wire[7:0] dout_8bit_ext,
    output wire valid_ext,
    input wire clk125M,
    input wire rd_rq,
    input wire[2:0]   IP
);

    wire [55:0] dout1, dout2, dout3, dout4, dout5, dout6;
    wire        valid1, valid2, valid3, valid4, valid5,valid6;
    wire        empty1, empty2, empty3, empty4, empty5,empty6;

    reg empty1_ext, empty2_ext, empty3_ext, empty4_ext, empty5_ext,empty6_ext;

    // ここは元の意図どおり（評価順はそのまま、代入だけ <= に）
    always @(posedge OSC) begin
        if (empty1 && empty2 && empty3 && empty4 &&empty5) begin
            empty1_ext <= 1'b0;
            empty2_ext <= 1'b0;
            empty3_ext <= 1'b0;
            empty4_ext <= 1'b0;
            empty5_ext <= 1'b0;
            empty6_ext <= 1'b1;
        end else if (empty1 && empty2 && empty3 && empty4) begin
            empty1_ext <= 1'b0;
            empty2_ext <= 1'b0;
            empty3_ext <= 1'b0;
            empty4_ext <= 1'b0;
            empty5_ext <= 1'b1;
            empty6_ext <= 1'b0;
        end else if (empty1 && empty2 && empty3) begin
            empty1_ext <= 1'b0;
            empty2_ext <= 1'b0;
            empty3_ext <= 1'b0;
            empty4_ext <= 1'b1;
            empty5_ext <= 1'b0;
            empty6_ext <= 1'b0;
        end else if (empty1 && empty2) begin
            empty1_ext <= 1'b0;
            empty2_ext <= 1'b0;
            empty3_ext <= 1'b1;
            empty4_ext <= 1'b0;
            empty5_ext <= 1'b0;
            empty6_ext <= 1'b0;
        end else if (empty1) begin
            empty1_ext <= 1'b0;
            empty2_ext <= 1'b1;
            empty3_ext <= 1'b0;
            empty4_ext <= 1'b0;
            empty5_ext <= 1'b0;
        end else begin
            empty1_ext <= 1'b1;
            empty2_ext <= 1'b0;
            empty3_ext <= 1'b0;
            empty4_ext <= 1'b0;
            empty5_ext <= 1'b0;
            empty6_ext <= 1'b0;
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

    // 64bit パケット {ID(8), DATA(56)}
    reg  [63:0] din;
    reg         wr_en;
    always @(posedge OSC) begin
        if (valid1)      begin din <= {3'd199,5'd1, dout1}; wr_en <= 1'b1; end
        else if (valid2) begin din <= {3'd199,5'd2, dout2}; wr_en <= 1'b1; end
        else if (valid3) begin din <= {3'd199,5'd3, dout3}; wr_en <= 1'b1; end
        else if (valid4) begin din <= {3'd199,5'd4, dout4}; wr_en <= 1'b1; end
        else if (valid5) begin din <= {3'd199,5'd5, dout5}; wr_en <= 1'b1; end
        else if (valid6) begin din <= {3'd199,5'd6, dout6}; wr_en <= 1'b1; end
        else             begin                         wr_en <= 1'b0; end
    end

    // FIFO 1（信号名の衝突/多重ドライブを回避）
    wire [7:0] dout_8bit;
    wire       valid;
    wire       empty;
    wire       full1;
    wire       rd_en = ~empty;

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
    wire wr_rst_busy;
    wire rd_rst_busy;
    
    fifo_generator_2 fifo_125M (
        .clk   (OSC),
        .srst  (srst),   // 上の rst に対応
        .din   (dout_8bit),     // 上の din
        .wr_en (valid),         // 上の wr_en
    
        .rd_en (rd_en_ext),     // 上の rd_en
        .dout  (dout_8bit_ext), // 上の dout
        .full  (full2),         // 上の full
        .empty (empty_ext),     // 上の empty
        .valid (valid_ext)      // 上の valid
    );


endmodule
