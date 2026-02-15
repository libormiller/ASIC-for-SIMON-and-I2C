`timescale 1ns/1ps
module simon_rounds (
    input wire clk,
    input wire rst,
    input wire [31:0] block,    // Plaintext
    input wire [63:0] key,      
    output reg [31:0] ciphertext,
    output reg done
);

    reg [5:0] round_ctr;
    reg [15:0] Lx, Rx;       
    wire [15:0] subkey;

    //generátor klíčů
    simon_key key_gen_inst (
        .clk(clk),
        .rst(rst),
        .key(key),
        .round_ctr(round_ctr),
        .subkey(subkey)
    );

    // faistelova funkce
    wire [15:0] Lx_rol1 = {Lx[14:0], Lx[15]};
    wire [15:0] Lx_rol8 = {Lx[7:0], Lx[15:8]};
    wire [15:0] Lx_rol2 = {Lx[13:0], Lx[15:14]};   
    wire [15:0] f_out = (Lx_rol1 & Lx_rol8) ^ Lx_rol2;

    always @(posedge clk) begin
        if (rst) begin
            round_ctr <= 0;
            done <= 0;
            ciphertext <= 0;
            Lx <= block[31:16]; 
            Rx <= block[15:0];
            
        end else begin
            if (round_ctr < 32) begin
                Lx <= Rx ^ f_out ^ subkey;
                Rx <= Lx; 
                
                round_ctr <= round_ctr + 1;
            end else begin
                if (!done) begin
                    done <= 1;
                    ciphertext <= {Lx, Rx}; 
                end
            end
        end
    end

endmodule