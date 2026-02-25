`timescale 1ns / 1ps
`default_nettype none

module tb_main;

    reg  input_clk_p;
    wire input_clk_n = ~input_clk_p;

    initial begin
        input_clk_p = 1'b0;
        forever #2.5 input_clk_p = ~input_clk_p;
    end

    reg IN1, IN2, IN3;
    reg IN4_p;
    wire IN4_n = ~IN4_p;
    reg IN5_p;
    wire IN5_n = ~IN5_p;

    initial begin
        IN1 = 0; IN2 = 0; IN3 = 0;
        IN4_p = 0; IN5_p = 0;
    end

    wire locked_out;

    main dut (
        .input_clk_p(input_clk_p),
        .input_clk_n(input_clk_n),

        .IN1(IN1),
        .IN2(IN2),
        .IN3(IN3),
        .IN4_p(IN4_p),
        .IN4_n(IN4_n),
        .IN5_p(IN5_p),
        .IN5_n(IN5_n),

        .locked_out(locked_out)
    );

    initial begin
        wait(locked_out);
        #1000;
        $finish;
    end

    initial begin
        #400;
        IN1 = 1; #6; IN1 = 0;
        #100;
        IN1 = 1; #6; IN1 = 0;
    end

endmodule

`default_nettype wire
