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
        IN1   = 0;
        IN2   = 0;
        IN3   = 0;
        IN4_p = 0;
        IN5_p = 0;
    end

    wire locked;

    main dut (
        // ポート名だけ main に合わせて修正
        .SYSCLK_200MP_IN(input_clk_p),
        .SYSCLK_200MN_IN(input_clk_n),

        .IN1(IN1),
        .IN2(IN2),
        .IN3(IN3),
        .IN4_p(IN4_p),
        .IN4_n(IN4_n),
        .IN5_p(IN5_p),
        .IN5_n(IN5_n)
        // .locked(locked) は main に存在しないので接続しない
    );

    // main 内部の locked を階層参照で見る
    assign locked = dut.locked;

    initial begin
        wait(locked);
        #1000;
        $finish;
    end

    initial begin
        #400;
        IN1 = 1; #6; IN1 = 0;
        #100;
        IN2 = 1; #6; IN2 = 0;
        #200; 
        IN1 =1; IN2=1;
        #6; IN1=0; IN2=0;
    end

//    initial begin
//        #400;
//        IN1 = 1;
//        IN2 = 1; 
//        #6; IN1 = 0;
//        #6; IN2 = 0;
//        #100;
//        IN1 = 1; #6; IN1 = 0;
//        #10;
//        IN2 = 1; #6; IN2 = 0;
//    end

endmodule

`default_nettype wire
