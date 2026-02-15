`timescale 1ns/1ps

module simon_top (
    input wire clk,
    input wire rst,      // Globální reset
    inout tri1 sda_pin,
    inout tri1 scl_pin
);

    // Tri state logika pro I2C (open drain)
    reg sda_master_en = 1; 
    reg scl_master_en = 1;

    //simulace v cocotb i2c master blbne se high-z prto master_en 
    assign sda_pin = ((sda_t == 1'b0 && sda_o == 1'b0) || (sda_master_en == 1'b0)) ? 1'b0 : 1'bz;
    assign scl_pin = ((scl_t == 1'b0 && scl_o == 1'b0) || (scl_master_en == 1'b0)) ? 1'b0 : 1'bz;
    assign sda_i = sda_pin;
    assign scl_i = scl_pin;

    // i2c signály
    wire [7:0] rx_data;
    wire rx_valid, rx_ready, rx_last;
    reg  [7:0] tx_data;
    reg  tx_valid;
    wire tx_ready, i2c_busy, i2c_addressed;

    //flow control, aby se nepřijímaly data během resetu
    reg rx_ready_reg;
    assign rx_ready = rx_ready_reg;

    // i2c slave instance (modul z https://github.com/alexforencich/verilog-i2c)
    i2c_slave #(
        .FILTER_LEN(1)
    ) my_i2c_inst (
        .clk(clk),
        .rst(rst),
        .scl_i(scl_i), .scl_o(scl_o), .scl_t(scl_t),
        .sda_i(sda_i), .sda_o(sda_o), .sda_t(sda_t),
        .enable(1'b1),
        .device_address(7'h50), //adresa tzn 0x50
        .device_address_mask(7'h7F), //maska i2c -> slave kontroluje všech 7 bit§ adresy
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

    // i2c registry
    reg [63:0] key_reg;     /* 0x00 - 0x07; klíč nahrává i2c master, protože není v IHP procesu 
    vytvořit jednorázové e-fusy, ppro přiřazení náhodného klíče ke každému vyrobenému modulu*/
    reg [31:0] block_reg;   // 0x08 - 0x0B
    reg [31:0] cipher_reg;  // 0x10 - 0x13 (Read only - výsledek)
    
    // i2c kontrolní registry
    reg core_start;         // Bit 0: 1=reset, 0=run
    reg core_mode;          // Bit 1: 0=encrypt, 1=decrypt
    
    wire [31:0] core_ciphertext_out;
    wire core_done;

    reg [7:0] reg_addr_ptr; // ukazatel adresy registrů
    reg addr_received;


    always @(posedge clk) begin
        if (rst) begin
            //inicializace registrů
            addr_received <= 1'b0;
            reg_addr_ptr  <= 8'h00;
            key_reg       <= 64'h0;
            block_reg     <= 32'h0;
            cipher_reg    <= 32'h0;
            core_start    <= 1'b0;
            core_mode     <= 1'b0;
            rx_ready_reg <= 1'b0;
        end else begin
            rx_ready_reg <= 1'b1;
            // modul simonu dopočítal ciphertext
            if (core_done) begin
                cipher_reg <= core_ciphertext_out;
            end

            // reset adresování při stop condition
            if (!i2c_addressed) begin
                addr_received <= 1'b0;
            end

            // zápis z I2C (Master -> Slave)
            if (rx_valid && rx_ready) begin
                if (!addr_received) begin
                    reg_addr_ptr  <= rx_data; // první byte je adresa registru
                    addr_received <= 1'b1;
                end else begin
                    case (reg_addr_ptr)
                        // klíč (64-bit)
                        8'h00: key_reg[7:0]   <= rx_data;
                        8'h01: key_reg[15:8]  <= rx_data;
                        8'h02: key_reg[23:16] <= rx_data;
                        8'h03: key_reg[31:24] <= rx_data;
                        8'h04: key_reg[39:32] <= rx_data;
                        8'h05: key_reg[47:40] <= rx_data;
                        8'h06: key_reg[55:48] <= rx_data;
                        8'h07: key_reg[63:56] <= rx_data;
                        // data Block (32-bit)
                        8'h08: block_reg[7:0]   <= rx_data;
                        8'h09: block_reg[15:8]  <= rx_data;
                        8'h0A: block_reg[23:16] <= rx_data;
                        8'h0B: block_reg[31:24] <= rx_data;
                        
                        // kontrolní registry (0x0C)
                        8'h0C: begin
                            core_start <= rx_data[0]; 
                            core_mode  <= rx_data[1]; 
                        end
                    endcase
                    // auto-inkrementace adresy pro burst zápis
                    reg_addr_ptr <= reg_addr_ptr + 1'b1;
                end
            end

            // inkrementace adresy při čtení
            if (tx_valid && tx_ready) begin
                reg_addr_ptr <= reg_addr_ptr + 1'b1;
            end
        end
    end

    // Čtení Slave -> Master)
    always @(*) begin
        tx_data  = 8'h00;
        tx_valid = i2c_addressed; 

        case (reg_addr_ptr)
            8'h10: tx_data = cipher_reg[7:0];
            8'h11: tx_data = cipher_reg[15:8];
            8'h12: tx_data = cipher_reg[23:16];
            8'h13: tx_data = cipher_reg[31:24];
            8'h14: tx_data = {6'b0, core_done, !core_done}; // status register (0x14): Bit 1=Done
            default: tx_data = 8'hFF; //když se master pokusí přečíst neznámou adresu
        endcase
    end

    // instance SIMON jádra
    simon_rounds simonCore (
        .clk(clk),
        .rst(core_start),       // řízeno registrem i2c na 0x0C[0]
        .mode(core_mode),       // řízeno registrem i2c na 0x0C[1]
        .block(block_reg),
        .key(key_reg),
        .ciphertext(core_ciphertext_out),
        .done(core_done)
    );

    // debug output soubor 
    /*
    initial begin
        $dumpfile("cocotb_waveform.vcd");
        $dumpvars(0, simon_top);
    end
    */
endmodule