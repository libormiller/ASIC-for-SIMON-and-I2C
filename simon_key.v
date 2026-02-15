`timescale 1ns/1ps

/*
modul generuje a rekonstruuje subklíče
toto je nejefektivnější možný postup z hlediska počtu nutných logických bran
*/

module simon_key (
    input wire clk,
    input wire rst,
    input wire [63:0] key,      // hlavní 64-bitový klíč
    input wire [5:0] round_ctr, // číslo aktuálního kola
    input wire dir,             // 0 = Encrypt, 1 = Decrypt
    output wire [15:0] subkey   // vygenerovaný podklíč pro dané kolo
);

    wire [61:0] z_seq = 62'b11111010001001010110000111001101111101000100101011000011100110;
    
    //subklíče
    reg [15:0] k0, k1, k2, k3;
    
    // generování K[i+4]
    wire [15:0] k3_ror3 = {k3[2:0], k3[15:3]};
    wire [15:0] tmp = k3_ror3 ^ k1;
    wire [15:0] tmp_ror1 = {tmp[0], tmp[15:1]};
    
    // který index proměnné z_seq se má použít
    wire [5:0] z_idx_calc = (dir) ? ((round_ctr >= 4) ? round_ctr - 4 : 0) : round_ctr;
    wire [5:0] z_idx_safe = (z_idx_calc > 61) ? 0 : (61 - z_idx_calc);
    wire z_bit = z_seq[z_idx_safe];

    // nový subklíč
    wire [15:0] k_next = 16'hFFFC ^ {15'b0, z_bit} ^ k0 ^ tmp ^ tmp_ror1;

    // Rekonstrukce K[i-1]
    wire [15:0] k2_ror3 = {k2[2:0], k2[15:3]};
    wire [15:0] tmp_rev = k2_ror3 ^ k0; 
    wire [15:0] tmp_rev_ror1 = {tmp_rev[0], tmp_rev[15:1]};
    
    // předchozí klíč
    wire [15:0] k_prev = k3 ^ 16'hFFFC ^ {15'b0, z_bit} ^ tmp_rev ^ tmp_rev_ror1;

    always @(posedge clk) begin
        if (rst) begin
            // načtení master klíče do registrů pro operace
            k0 <= key[15:0];
            k1 <= key[31:16];
            k2 <= key[47:32];
            k3 <= key[63:48];
        end else begin
            if (!dir) begin
                // posuv VLEVO generujeme nový subklíč
                k0 <= k1; k1 <= k2; k2 <= k3; k3 <= k_next;
            end else begin
                // posuv VPRAVO rekonstruujeme starý subklíč
                k3 <= k2; k2 <= k1; k1 <= k0; k0 <= k_prev;
            end
        end
    end

    // výstupní mux
    assign subkey = (dir) ? k3 : k0;

endmodule