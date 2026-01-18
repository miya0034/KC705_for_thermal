`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/07 17:03:21
// Design Name: 
// Module Name: COUNT
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module COUNT(
    input  wire clk_out,
    input  wire locked,
    output reg[54:0] counter
    );
    
    always @(posedge clk_out) begin
        if (!locked)
            counter <= 54'b0;        // lockedが0の間はリセット
        else
            counter <= counter + 1;  // 立上りごとに+1
    end
    
    
endmodule
