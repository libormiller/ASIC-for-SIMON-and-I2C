`timescale 1ns/1ps

module tb_simon_key;

    reg clk;
    reg rst;
    reg [63:0] key;
    reg [5:0] round_ctr;
    reg dir;
    wire [15:0] subkey;

    // Instance testovaného modulu
    simon_key uut (
        .clk(clk),
        .rst(rst),
        .key(key),
        .round_ctr(round_ctr),
        .dir(dir),
        .subkey(subkey)
    );

    // Generování hodin
    always #5 clk = ~clk;

    initial begin
        // Dumpování vln pro GTKWave
        $dumpfile("key_debug.vcd");
        $dumpvars(0, tb_simon_key);

        // --- 1. INIT ---
        clk = 0;
        rst = 1;
        // Testovací klíč: 0x1918111009080100 (SIMON32/64 example key)
        key = 64'h1918111009080100; 
        dir = 0; // Forward
        round_ctr = 0;
        
        #10;
        rst = 0;
        $display("--- START FORWARD (PRECOMPUTE) ---");

        // --- 2. FORWARD LOOP (0 to 27 = 28 cyklů) ---
        // Simulujeme chování FSM v módu S_PRECOMP
        // Po 28 taktech by měly registry držet k28, k29, k30, k31
        repeat (28) begin
            $display("Time: %t | Round: %d | Subkey (k0): %h | Internal k3: %h", $time, round_ctr, subkey, uut.k3);
            @(posedge clk);
            round_ctr = round_ctr + 1;
        end

        // Kontrola stavu před přepnutím
        $display("--- PRECOMPUTE DONE ---");
        $display("Expecting k31 at output (via k3 in Reverse mode).");
        $display("Current Regs: k0=%h k1=%h k2=%h k3=%h", uut.k0, uut.k1, uut.k2, uut.k3);
        
        // --- 3. REVERSE LOOP (31 down to 0) ---
        dir = 1; // Reverse mode
        round_ctr = 31; // FSM nastaví na 31
        
        $display("--- START REVERSE (DECRYPT) ---");
        
        repeat (32) begin
            // V reverse módu je subkey brán z k3 (pokud je moje oprava správně)
            // nebo z k0 (pokud je původní). Sledujeme, co leze ven.
            $display("Time: %t | Round: %d | OUTPUT SUBKEY: %h", $time, round_ctr, subkey);
            
            @(posedge clk);
            if (round_ctr > 0) round_ctr = round_ctr - 1;
        end

        $display("--- DONE ---");
        $finish;
    end

endmodule