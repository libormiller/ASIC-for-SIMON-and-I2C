module simon_top (
    input wire clk,
    input wire rst,      // Active High Reset
    inout tri1 sda_pin,
    inout tri1 scl_pin
);

// --- 2. I2C Fyzická vrstva (Oprava pro simulaci 'z' jako '1') ---
    reg sda_master_en = 1; 
    reg scl_master_en = 1;

    // --- Sloučení Master a Slave driverů (Wired-AND logika) ---
    // Pin jde k nule, pokud k nule táhne Master NEBO Slave. Jinak je ve stavu 'z'.
    assign sda_pin = ((sda_t == 1'b0 && sda_o == 1'b0) || (sda_master_en == 1'b0)) ? 1'b0 : 1'bz;
    assign scl_pin = ((scl_t == 1'b0 && scl_o == 1'b0) || (scl_master_en == 1'b0)) ? 1'b0 : 1'bz;

    // Vstup pro oba moduly (Slave i Master přes Cocotb) zůstává stejný
    assign sda_i = sda_pin;
    assign scl_i = scl_pin;


    // --- 3. Propojení signálů ---
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_ready;
    wire       rx_last;

    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;

    wire       i2c_busy;
    wire       i2c_addressed;

    // Jsme připraveni přijímat, pokud neběží výpočet (zjednodušeno)
    assign rx_ready = 1'b1;

    // --- 4. Instanciace I2C Slave ---
    i2c_slave #(
        .FILTER_LEN(1)
    ) my_i2c_inst (
        .clk(clk),
        .rst(rst),
        .scl_i(scl_i), .scl_o(scl_o), .scl_t(scl_t),
        .sda_i(sda_i), .sda_o(sda_o), .sda_t(sda_t),
        .enable(1'b1),
        .device_address(7'h50),
        .device_address_mask(7'h7F),
        .busy(i2c_busy),
        .bus_addressed(i2c_addressed),
        .m_axis_data_tdata(rx_data),
        .m_axis_data_tvalid(rx_valid),
        .m_axis_data_tready(rx_ready),
        .m_axis_data_tlast(rx_last),
        .s_axis_data_tdata(tx_data),
        .s_axis_data_tvalid(tx_valid),
        .s_axis_data_tready(tx_ready),
        .s_axis_data_tlast(1'b0),
        .release_bus(1'b0) 
    );

    // --- 5. Vnitřní registry ---
    reg [63:0] key_reg;
    reg [31:0] block_reg;
    reg [31:0] cipher_reg;
    reg        core_start;
    
    wire [31:0] core_ciphertext_out;
    wire        core_done;

    reg [7:0] reg_addr_ptr;
    reg       addr_received;

    // --- 6. JEDNOTNÁ SEKVENČNÍ LOGIKA (Zápis a správa registru) ---
    // Vše, co mění hodnotu v registrech, musí být zde.
    always @(posedge clk) begin
        if (rst) begin
            addr_received <= 1'b0;
            reg_addr_ptr  <= 8'h00;
            key_reg       <= 64'h0;
            block_reg     <= 32'h0;
            cipher_reg    <= 32'h0;
            core_start    <= 1'b0;
        end else begin
            // Pulzní signál pro start jádra
            core_start <= 1'b0;

            // Pokud SIMON do počítal, ulož výsledek
            if (core_done) begin
                cipher_reg <= core_ciphertext_out;
            end

            // Resetování stavu adresy po skončení I2C transakce
            if (!i2c_addressed) begin
                addr_received <= 1'b0;
            end

            // LOGIKA ZÁPISU (Master -> Slave)
            if (rx_valid && rx_ready) begin
                if (!addr_received) begin
                    // První bajt po startu je adresa registru
                    reg_addr_ptr  <= rx_data;
                    addr_received <= 1'b1;
                end else begin
                    // Další bajty jsou data do registrů
                    case (reg_addr_ptr)
                        8'h00: key_reg[7:0]   <= rx_data;
                        8'h01: key_reg[15:8]  <= rx_data;
                        8'h02: key_reg[23:16] <= rx_data;
                        8'h03: key_reg[31:24] <= rx_data;
                        8'h04: key_reg[39:32] <= rx_data;
                        8'h05: key_reg[47:40] <= rx_data;
                        8'h06: key_reg[55:48] <= rx_data;
                        8'h07: key_reg[63:56] <= rx_data;
                        8'h08: block_reg[7:0]   <= rx_data;
                        8'h09: block_reg[15:8]  <= rx_data;
                        8'h0A: block_reg[23:16] <= rx_data;
                        8'h0B: block_reg[31:24] <= rx_data;
                        8'h0C: if (rx_data[0]) core_start <= 1'b1;
                    endcase
                    // Auto-inkrementace po zápisu bajtu
                    reg_addr_ptr <= reg_addr_ptr + 1'b1;
                end
            end

            // LOGIKA ČTENÍ - Inkrementace (Slave -> Master)
            // Posuneme adresu až když I2C modul potvrdí odeslání bajtu
            if (tx_valid && tx_ready) begin
                reg_addr_ptr <= reg_addr_ptr + 1'b1;
            end
        end
    end

    // --- 7. KOMBINAČNÍ LOGIKA PRO ČTENÍ ---
    // Tady se jen vybírá, co se má poslat na sběrnici (multiplexor)
    always @(*) begin
        // Výchozí hodnoty pro případ nečinnosti
        tx_data  = 8'h00;
        tx_valid = i2c_addressed; // Jsme validní, pokud nás Master oslovil pro čtení

        case (reg_addr_ptr)
            8'h10: tx_data = cipher_reg[7:0];
            8'h11: tx_data = cipher_reg[15:8];
            8'h12: tx_data = cipher_reg[23:16];
            8'h13: tx_data = cipher_reg[31:24];
            8'h14: tx_data = {6'b0, core_done, !core_done}; // bit 1=Done, bit 0=Busy (not done)
            default: tx_data = 8'hFF; // Čtení neexistujícího registru
        endcase
    end

    // --- 8. SIMON Core Integrace ---
    simon_rounds simonCore (
        .clk(clk),
        .rst(core_start),
        .block(block_reg),
        .key(key_reg),
        .ciphertext(core_ciphertext_out),
        .done(core_done)
    );
/*
initial begin
        $dumpfile("cocotb_waveform.vcd");
        $dumpvars(0, simon_top);
    end
*/
endmodule