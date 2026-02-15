`timescale 1ns / 1ps

module tb_simon_full;

    // --- 1. Signály a Konfigurace ---
    reg clk;
    reg rst;

    // I2C Sběrnice
    wire sda;
    wire scl;

    // Řízení Mastera (Testbenche)
    reg sda_drive; 
    reg scl_drive; 

    // Proměnné pro čtení/zápis
    reg [7:0] read_byte_val;
    reg ack_bit;
    
    // Globální pole pro data (aby nemusely být v argumentech tasku)
    reg [7:0] captured_data [0:3]; 

    // --- 2. Instanciace DUT ---
    simon_top dut (
        .clk(clk),
        .rst(rst),
        .sda_pin(sda),
        .scl_pin(scl)
    );

    // --- 3. Open Drain Logika a Pull-upy ---
    assign sda = (sda_drive == 1'b0) ? 1'b0 : 1'bz;
    assign scl = (scl_drive == 1'b0) ? 1'b0 : 1'bz;

    pullup(sda);
    pullup(scl);

    // --- 4. Generátor Hodin (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- 5. I2C Timing (100kHz) ---
    localparam DELAY = 5000; 
    localparam ADDR_WR = 8'hA0; 
    localparam ADDR_RD = 8'hA1;

    // =================================================================
    // DEBUG MONITOR
    // =================================================================
    always @(dut.simonCore.state) begin
        case(dut.simonCore.state)
            0: $display("[INTERNAL %0t] FSM State: IDLE", $time);
            1: $display("[INTERNAL %0t] FSM State: PRECOMPUTE (Winding keys forward...)", $time);
            2: $display("[INTERNAL %0t] FSM State: CALCULATION (Working...)", $time);
            default: $display("[INTERNAL %0t] FSM State: UNKNOWN (%d)", $time, dut.simonCore.state);
        endcase
    end

    always @(dut.core_mode) begin
        if (dut.core_mode == 1'b0) $display("[INTERNAL %0t] Core Mode Latched: ENCRYPT", $time);
        else                       $display("[INTERNAL %0t] Core Mode Latched: DECRYPT", $time);
    end
    
    always @(dut.simonCore.round_ctr) begin
        if (dut.simonCore.state == 2) begin 
             if (dut.simonCore.round_ctr % 5 == 0 || dut.simonCore.round_ctr == 0 || dut.simonCore.round_ctr == 31) begin
                 $display("[INTERNAL %0t] Round: %d | Lx: %h | Rx: %h | Subkey: %h", 
                          $time, dut.simonCore.round_ctr, dut.simonCore.Lx, dut.simonCore.Rx, dut.simonCore.subkey);
             end
        end
    end

    // =================================================================
    // HLAVNÍ TESTOVACÍ SEKVENCE
    // =================================================================
    initial begin
        $dumpfile("simon_full_test.vcd");
        $dumpvars(0, tb_simon_full);
        $dumpvars(0, dut.simonCore); 
        
        $display("==================================================");
        $display("   START SIMON 32/64 FULL TEST (ENC + DEC)");
        $display("==================================================");

        // A. Inicializace
        rst = 1;
        sda_drive = 1;
        scl_drive = 1;
        #200;
        rst = 0;
        $display("[T=%0t] Reset uvolnen.", $time);
        #2000;

        // -----------------------------------------------------------
        // FÁZE 1: ENCRYPTION
        // -----------------------------------------------------------
        $display("\n--- [FÁZE 1] ENCRYPTION ---");
        
        $display("Zapisuji KLIC...");
        i2c_write_reg_block(8'h00, {8'h19, 8'h18, 8'h11, 8'h10, 8'h09, 8'h08, 8'h01, 8'h00});
        
        $display("Zapisuji PLAINTEXT (0x65656877)...");
        i2c_write_reg_block_32(8'h08, {8'h65, 8'h65, 8'h68, 8'h77});

        $display("Spoustim ENCRYPTION (Cmd 0x01)...");
        i2c_start();
        i2c_write_byte(ADDR_WR);
        i2c_write_byte(8'h0C);
        i2c_write_byte(8'h01); // Start=1, Mode=Enc
        i2c_stop();

        #DELAY; 
        i2c_start();
        i2c_write_byte(ADDR_WR);
        i2c_write_byte(8'h0C);
        i2c_write_byte(8'h00); // Start=0, Mode=Enc
        i2c_stop();

        $display("Cekam na vypocet...");
        #20000; 

        $display("Ctu Ciphertext...");
        // Funkce nyní zapíše výsledek do globálního pole 'captured_data'
        i2c_read_4bytes_global(); 
        
        $display("Ciphertext: %h %h %h %h (Ocekavano: BB E9 9B C6)", 
                 captured_data[3], captured_data[2], captured_data[1], captured_data[0]);

        if (captured_data[0] == 8'hBB && captured_data[3] == 8'hC6) 
            $display("[CHECK] ENCRYPTION OK");
        else begin
            $display("[CHECK] ENCRYPTION FAILED! Koncim.");
            $finish;
        end

        // -----------------------------------------------------------
        // FÁZE 2: DECRYPTION
        // -----------------------------------------------------------
        $display("\n--- [FÁZE 2] DECRYPTION ---");
        
        $display("Zapisuji CIPHERTEXT zpet na vstup (0x08)...");
        // Použijeme data z captured_data
        i2c_write_reg_block_32(8'h08, {captured_data[3], captured_data[2], captured_data[1], captured_data[0]});

        $display("Spoustim DECRYPTION (Cmd 0x03)...");
        i2c_start();
        i2c_write_byte(ADDR_WR);
        i2c_write_byte(8'h0C);
        i2c_write_byte(8'h03); // Start=1, Mode=DEC
        i2c_stop();

        #DELAY;
        i2c_start();
        i2c_write_byte(ADDR_WR);
        i2c_write_byte(8'h0C);
        i2c_write_byte(8'h02); // Start=0, Mode=DEC
        i2c_stop();

        $display("Cekam na vypocet (Decryption)...");
        #40000; 

        $display("Ctu vysledek (Plaintext)...");
        i2c_read_4bytes_global(); // Zapíše do captured_data

        $display("Decrypted: %h %h %h %h (Ocekavano: 77 68 65 65)", 
                 captured_data[3], captured_data[2], captured_data[1], captured_data[0]);

        if (captured_data[0] == 8'h77 && captured_data[3] == 8'h65) 
            $display("\n[SUCCESS] DECRYPTION OK! System plne funkcni.");
        else
            $display("\n[FAILURE] DECRYPTION FAILED.");

        $display("==================================================");
        #2000;
        $finish;
    end

    // =================================================================
    // POMOCNÉ TASKS
    // =================================================================

    task i2c_write_reg_block;
        input [7:0] start_reg;
        input [63:0] data; 
        integer i;
        begin
            i2c_start();
            i2c_write_byte(ADDR_WR);
            i2c_write_byte(start_reg);
            for(i=0; i<8; i=i+1) begin
                i2c_write_byte(data[i*8 +: 8]);
            end
            i2c_stop();
            #DELAY;
        end
    endtask

    task i2c_write_reg_block_32;
        input [7:0] start_reg;
        input [31:0] data; 
        integer i;
        begin
            i2c_start();
            i2c_write_byte(ADDR_WR);
            i2c_write_byte(start_reg);
            for(i=0; i<4; i=i+1) begin
                i2c_write_byte(data[i*8 +: 8]);
            end
            i2c_stop();
            #DELAY;
        end
    endtask

    // Změna: Žádné výstupní argumenty, zápis do globálního pole
    task i2c_read_4bytes_global;
        begin
            // 1. Nastavit pointer na 0x10
            i2c_start();
            i2c_write_byte(ADDR_WR);
            i2c_write_byte(8'h10);
            i2c_stop(); 
            #DELAY;
            // 2. Číst data
            i2c_start();
            i2c_write_byte(ADDR_RD);
            i2c_read_byte(0); captured_data[0] = read_byte_val;
            i2c_read_byte(0); captured_data[1] = read_byte_val;
            i2c_read_byte(0); captured_data[2] = read_byte_val;
            i2c_read_byte(1); captured_data[3] = read_byte_val; // NACK last
            i2c_stop();
        end
    endtask

    task i2c_start;
        begin
            sda_drive = 1; scl_drive = 1; #DELAY;
            sda_drive = 0; #DELAY;
            scl_drive = 0; #DELAY;
        end
    endtask

    task i2c_stop;
        begin
            sda_drive = 0; scl_drive = 0; #DELAY;
            scl_drive = 1; #DELAY;
            sda_drive = 1; #DELAY;
        end
    endtask

    task i2c_write_byte;
        input [7:0] data;
        integer i;
        begin
            for (i=7; i>=0; i=i-1) begin
                sda_drive = data[i]; #DELAY;
                scl_drive = 1; #DELAY; #DELAY;
                scl_drive = 0; #DELAY;
            end
            sda_drive = 1; #DELAY;
            scl_drive = 1; #DELAY;
            ack_bit = sda;
            #DELAY;
            scl_drive = 0; #DELAY;
        end
    endtask

    task i2c_read_byte;
        input send_nack; 
        integer i;
        begin
            read_byte_val = 0;
            sda_drive = 1; 
            for (i=7; i>=0; i=i-1) begin
                #DELAY; scl_drive = 1; #DELAY;
                read_byte_val[i] = sda;
                #DELAY; scl_drive = 0; #DELAY;
            end
            sda_drive = send_nack; 
            #DELAY; scl_drive = 1; #DELAY; #DELAY;
            scl_drive = 0; #DELAY;
            sda_drive = 1; 
        end
    endtask

endmodule