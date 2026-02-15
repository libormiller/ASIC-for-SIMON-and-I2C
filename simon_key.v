`timescale 1ns/1ps
module simon_key (
    input wire clk,
    input wire rst,
    input wire [63:0] key,      // celý 64bit klíč
    input wire [5:0] round_ctr, // čítač roundů (potřeba pro Z-sekvenci)
    output wire [15:0] subkey   // aktuální klíč (k0) pro danoý round
);

    wire [61:0] z_seq = 62'b11111010001001010110000111001101111101000100101011000011100110;
    
    // vnitřní registry klíčů
    reg [15:0] k0, k1, k2, k3;

    // logika výpočtu nového klíče
    wire [15:0] k3_ror3 = {k3[2:0], k3[15:3]};
    wire [15:0] tmp = k3_ror3 ^ k1;
    wire [15:0] tmp_ror1 = {tmp[0], tmp[15:1]};
    
    wire z_bit = z_seq[61 - round_ctr]; 
    wire [15:0] k_new = 16'hFFFC ^ {15'b0, z_bit} ^ k0 ^ tmp ^ tmp_ror1;

    always @(posedge clk) begin
        if (rst) begin
            // načtení klíče (LSB -> k0)
            k0 <= key[15:0];
            k1 <= key[31:16];
            k2 <= key[47:32];
            k3 <= key[63:48];
        end else begin
            if (round_ctr < 32) begin
                // posun registrů
                k0 <= k1;
                k1 <= k2;
                k2 <= k3;
                k3 <= k_new;
            end
        end
    end

//výsledný subkey
    assign subkey = k0;

endmodule