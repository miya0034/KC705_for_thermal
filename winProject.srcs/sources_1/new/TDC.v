`timescale 1ns / 1ps

module TDC(
    input  wire        clk_out,
    input  wire        locked,
    input  wire        IN,
    output reg  [55:0] counter2,
    output reg         wr_en
);

    wire [54:0] counter;

    COUNT count(
        .clk_out (clk_out),
        .locked  (locked),
        .counter (counter)
    );

    reg in_sample, in_sample_d;

    always @(posedge clk_out) begin
        if (!locked) begin
            in_sample   <= 1'b0;
            in_sample_d <= 1'b0;
            counter2    <= 56'd0;
            wr_en       <= 1'b0;
        end else begin
            //立ち上がり検出
            in_sample_d <= in_sample;
            in_sample   <= IN;

            // 立上り判定（1クロックパルス）
            wr_en <= in_sample & ~in_sample_d;

            // 立上りが来たクロックでカウンタをラッチ
            if (in_sample & ~in_sample_d)
                counter2 <= {1'b0, counter};
        end
    end
    

endmodule