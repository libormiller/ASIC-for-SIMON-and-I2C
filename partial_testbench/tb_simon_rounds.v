`timescale 1ns/1ps

module simon_rounds (
    input wire clk,
    input wire rst,
    input wire mode,         // 0=Encrypt, 1=Decrypt
    input wire [31:0] block,
    input wire [63:0] key,
    output reg [31:0] ciphertext,
    output reg done
);
    reg [5:0] round_ctr;
    reg [15:0] Lx, Rx;       
    wire [15:0] subkey;

    localparam S_IDLE = 0, S_PRECOMP = 1, S_CALC = 2;
    reg [1:0] state;
    
    // Inicializace pro simulaci, aby nedělal "xxxx" v logu před prvním taktem
    reg key_dir = 0;
    
    simon_key key_gen_inst (
        .clk(clk),
        .rst(rst),
        .key(key),
        .round_ctr(round_ctr),
        .dir(key_dir),
        .subkey(subkey)
    );

    wire [15:0] Lx_rol1 = {Lx[14:0], Lx[15]};
    wire [15:0] Lx_rol8 = {Lx[7:0], Lx[15:8]};
    wire [15:0] Lx_rol2 = {Lx[13:0], Lx[15:14]};   
    wire [15:0] f_out = (Lx_rol1 & Lx_rol8) ^ Lx_rol2;

    wire [15:0] next_Lx = Rx ^ f_out ^ subkey;
    wire [15:0] next_Rx = Lx;

    always @(posedge clk) begin
        if (rst) begin
            state <= (mode) ? S_PRECOMP : S_CALC;
            done <= 0;
            round_ctr <= 0;
            key_dir <= 0; 
            ciphertext <= 0;

            if (mode) begin Lx <= block[15:0];  Rx <= block[31:16]; end
            else      begin Lx <= block[31:16]; Rx <= block[15:0];  end

        end else begin
            case (state)
                S_IDLE: begin
                    // Čekáme na reset/start, držíme hodnoty
                    done <= 1; // Udržujeme done high
                end

                S_PRECOMP: begin
                    if (round_ctr < 27) begin
                        round_ctr <= round_ctr + 1;
                    end else begin
                        state <= S_CALC;
                        round_ctr <= 31; 
                        key_dir <= 1;
                    end
                end

                S_CALC: begin
                    if (!mode) begin // --- ENCRYPT ---
                        if (round_ctr < 31) begin
                            // Standardní update
                            Lx <= next_Lx;
                            Rx <= next_Rx;
                            round_ctr <= round_ctr + 1;
                        end else begin
                            // Konec: Uložit výsledek a ZASTAVIT
                            done <= 1;
                            ciphertext <= {next_Lx, next_Rx}; 
                            state <= S_IDLE; // <--- DŮLEŽITÉ: Přechod do IDLE
                        end
                    end else begin   // --- DECRYPT ---
                        if (round_ctr > 0) begin
                            // Standardní update
                            Lx <= next_Lx;
                            Rx <= next_Rx;
                            round_ctr <= round_ctr - 1;
                        end else begin
                            // Konec: Uložit výsledek a ZASTAVIT
                            done <= 1;
                            ciphertext <= {next_Rx, next_Lx}; 
                            state <= S_IDLE; // <--- DŮLEŽITÉ: Přechod do IDLE
                        end
                    end
                end
            endcase
        end
    end
endmodule