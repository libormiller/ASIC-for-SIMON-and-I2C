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
    reg [7:0] captured_cipher [0:3]; // Pro uložení výsledku

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
    // Perioda 10us. Půlperioda 5us (5000ns).
    localparam DELAY = 5000; 

    // Adresa zařízení (write=0xA0, read=0xA1)
    localparam ADDR_WR = 8'hA0; 
    localparam ADDR_RD = 8'hA1;

    // --- 6. HLAVNÍ TESTOVACÍ SEKVENCE ---
    initial begin
        $dumpfile("simon_full_test.vcd");
        $dumpvars(0, tb_simon_full);
        
        $display("==================================================");
        $display("   START SIMON 32/64 FULL VERILOG TESTBENCH");
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
        // B. Zápis KLÍČE (NSA Vector: 0x1918111009080100)
        // Little Endian zápis: 00, 01, 08, 09, 10, 11, 18, 19
        // -----------------------------------------------------------
        $display("\n[KROK 1] Zapisuji KLIC...");
        i2c_start();
        i2c_write(ADDR_WR);      // Adresa zarizeni + Write
        i2c_write(8'h00);        // Adresa registru (Pointer)
        
        i2c_write(8'h00);        // Byte 0
        i2c_write(8'h01);        // Byte 1
        i2c_write(8'h08);        // Byte 2
        i2c_write(8'h09);        // Byte 3
        i2c_write(8'h10);        // Byte 4
        i2c_write(8'h11);        // Byte 5
        i2c_write(8'h18);        // Byte 6
        i2c_write(8'h19);        // Byte 7
        
        i2c_stop();
        #DELAY;

        // -----------------------------------------------------------
        // C. Zápis PLAINTEXTU (NSA Vector: 0x65656877)
        // Little Endian: 77, 68, 65, 65
        // -----------------------------------------------------------
        $display("\n[KROK 2] Zapisuji BLOK (Plaintext)...");
        i2c_start();
        i2c_write(ADDR_WR);
        i2c_write(8'h08);        // Adresa registru (Block)
        
        i2c_write(8'h77);        // Byte 0 (LSB)
        i2c_write(8'h68);        // Byte 1
        i2c_write(8'h65);        // Byte 2
        i2c_write(8'h65);        // Byte 3 (MSB)
        
        i2c_stop();
        #DELAY;

        // -----------------------------------------------------------
        // D. Spuštění VÝPOČTU (Reg 0x0C <= 0x01)
        // -----------------------------------------------------------
        $display("\n[KROK 3] Spoustim VYPOČET...");
        i2c_start();
        i2c_write(ADDR_WR);
        i2c_write(8'h0C);        // Adresa registru (Control)
        i2c_write(8'h01);        // Command Start
        i2c_stop();

        // -----------------------------------------------------------
        // E. Čekání na výpočet
        // -----------------------------------------------------------
        $display("\n[KROK 4] Cekam na dokonceni (Busy wait)...");
        #20000; // 20us (dostatecne pro 32 rund pri 100MHz)

        // -----------------------------------------------------------
        // F. Čtení VÝSLEDKU (z reg 0x10)
        // Očekáváme: 0xc69be9bb -> Little Endian: bb, e9, 9b, c6
        // -----------------------------------------------------------
        $display("\n[KROK 5] Ctu VYSLEDEK...");
        
        // 1. Nastavit pointer na 0x10
        i2c_start();
        i2c_write(ADDR_WR);
        i2c_write(8'h10);        // Adresa registru (Cipher output)
        i2c_stop(); // Restart nebo Stop+Start (uděláme Stop+Start pro jistotu)
        
        #DELAY;

        // 2. Číst 4 bajty
        i2c_start();
        i2c_write(ADDR_RD); // Adresa + READ
        
        i2c_read(1'b0); captured_cipher[0] = read_byte_val; // ACK
        i2c_read(1'b0); captured_cipher[1] = read_byte_val; // ACK
        i2c_read(1'b0); captured_cipher[2] = read_byte_val; // ACK
        i2c_read(1'b1); captured_cipher[3] = read_byte_val; // NACK (poslední bajt)
        
        i2c_stop();

        // -----------------------------------------------------------
        // G. Vyhodnocení
        // -----------------------------------------------------------
        $display("\n==================================================");
        $display("   VYSLEDKY TESTU");
        $display("==================================================");
        $display("Ocekavano: BB E9 9B C6");
        $display("Precteno : %h %h %h %h", captured_cipher[0], captured_cipher[1], captured_cipher[2], captured_cipher[3]);

        if (captured_cipher[0] == 8'hBB && 
            captured_cipher[1] == 8'hE9 && 
            captured_cipher[2] == 8'h9B && 
            captured_cipher[3] == 8'hC6) begin
            
            $display("\n[SUCCESS] GRATULUJI! Sifra sedi presne.");
        end else begin
            $display("\n[FAILURE] CHYBA! Data nesedi.");
        end
        $display("==================================================");
        
        #2000;
        $finish;
    end

    // =================================================================
    // ÚLOHY (TASKS) PRO I2C BIT-BANGING
    // =================================================================

    // --- I2C START ---
    task i2c_start;
        begin
            sda_drive = 1;
            scl_drive = 1;
            #DELAY;
            sda_drive = 0; // SDA dolů při SCL High -> START
            #DELAY;
            scl_drive = 0;
            #DELAY;
        end
    endtask

    // --- I2C STOP ---
    task i2c_stop;
        begin
            sda_drive = 0;
            scl_drive = 0;
            #DELAY;
            scl_drive = 1;
            #DELAY;
            sda_drive = 1; // SDA nahoru při SCL High -> STOP
            #DELAY;
        end
    endtask

    // --- I2C WRITE BYTE (Vrací ACK/NACK v proměnné ack_bit) ---
    task i2c_write;
        input [7:0] data;
        integer i;
        begin
            // 8 datových bitů
            for (i=7; i>=0; i=i-1) begin
                sda_drive = data[i]; // Nastavit data
                #DELAY;
                scl_drive = 1;       // Clock High
                #DELAY; // Wait
                #DELAY; // Wait more
                scl_drive = 0;       // Clock Low
                #DELAY;
            end

            // 9. bit (ACK)
            sda_drive = 1; // Master uvolní SDA
            #DELAY;
            scl_drive = 1; // Clock High (Slave odpovídá)
            #DELAY;
            
            ack_bit = sda; // Vzorkování ACK
            if (ack_bit == 1'b0) 
                $display("\t-> Write %h : ACK OK", data);
            else 
                $display("\t-> Write %h : NACK! (Chyba)", data);
                
            #DELAY;
            scl_drive = 0; // Clock Low
            #DELAY;
        end
    endtask

    // --- I2C READ BYTE ---
    task i2c_read;
        input send_ack; // 0 = poslat ACK, 1 = poslat NACK
        integer i;
        begin
            read_byte_val = 0;
            sda_drive = 1; // Uvolnit SDA pro čtení

            // 8 datových bitů
            for (i=7; i>=0; i=i-1) begin
                #DELAY;
                scl_drive = 1; // Clock High
                #DELAY;
                read_byte_val[i] = sda; // Vzorkování dat
                #DELAY;
                scl_drive = 0; // Clock Low
                #DELAY;
            end

            // 9. bit (Odeslání ACK/NACK Masterem)
            sda_drive = send_ack; // Master řídí ACK/NACK
            #DELAY;
            scl_drive = 1;
            #DELAY;
            #DELAY;
            scl_drive = 0;
            #DELAY;
            sda_drive = 1; // Uvolnit po ACK
            
            $display("\t<- Read Byte: %h (Ack sent: %b)", read_byte_val, !send_ack);
        end
    endtask

endmodule