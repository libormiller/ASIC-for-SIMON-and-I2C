import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, Lock, Combine 
from cocotbext.i2c import I2cMaster

# referenční model simon 32/64
def rotl(x, k): return ((x << k) & 0xFFFF) | (x >> (16 - k))
def rotr(x, k): return ((x >> k) & 0xFFFF) | ((x << (16 - k)) & 0xFFFF)

def simon_32_64_gold(plaintext_int, key_int):
    key = [(key_int >> (i*16)) & 0xFFFF for i in range(4)]
    L = (plaintext_int >> 16) & 0xFFFF; R = (plaintext_int >> 0) & 0xFFFF
    z0 = 0b11111010001001010110000111001101111101000100101011000011100110
    for i in range(32):
        curr_k = key[0]
        f_val = (rotl(L, 1) & rotl(L, 8)) ^ rotl(L, 2)
        new_L = R ^ f_val ^ curr_k
        new_R = L; L = new_L; R = new_R
        c = 0xFFFC; z_bit = (z0 >> (61 - i)) & 1
        tmp = rotr(key[3], 3) ^ key[1]; tmp_ror1 = rotr(tmp, 1)
        k_new = c ^ z_bit ^ key[0] ^ tmp ^ tmp_ror1
        key = key[1:] + [k_new]
    return ((L & 0xFFFF) << 16) | (R & 0xFFFF)

I2C_ADDR = 0x50 

@cocotb.test()
async def test_simon_massive_multithreaded(dut):
    """
    Testuje náhodně ENCRYPT i DECRYPT operace s manuálním řízením Start bitu.
    """
    
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    i2c = I2cMaster(sda=dut.sda_pin, scl=dut.scl_pin, speed=100e3)

    # open-drain konfigurace pro simulaci
    def open_drain_sda(val): dut.sda_master_en.value = 1 if val else 0
    def open_drain_scl(val): dut.scl_master_en.value = 1 if val else 0
    i2c._set_sda = open_drain_sda
    i2c._set_scl = open_drain_scl
    
    dut.rst.value = 1
    await Timer(200, unit="ns")
    dut.rst.value = 0
    await Timer(1000, unit="ns")
    
    bus_lock = Lock()
    NUM_THREADS = 12
    ITERS_PER_THREAD = 1


    #každé vlákno si spowne tento worker; vytvoří náhodné klíče,
    #náhodné plaintexty a náhodný mód šifrování/dešifrování, 
    #celé to zvaliduje pomocí referenčního modelu simon_32_64_gold
    async def stress_worker(thread_id):
        for i in range(ITERS_PER_THREAD):
            mode = random.randint(0, 1) # 0=Enc, 1=Dec
            
            k = random.getrandbits(64)
            data_in = random.getrandbits(32)
            
            if mode == 0:
                # Zašifruj
                exp = simon_32_64_gold(data_in, k)
                cmd_load = 0x01 # Bit0=1 (Start), Bit1=0 (Enc)
                cmd_run  = 0x00 # Bit0=0 (Run),   Bit1=0 (Enc)
                mode_str = "ENC"
                input_val = data_in
            else:
                # Rozšifruj
                plain = data_in
                input_val = simon_32_64_gold(plain, k)
                exp = plain
                cmd_load = 0x03 # Bit0=1 (Start), Bit1=1 (Dec)
                cmd_run  = 0x02 # Bit0=0 (Run),   Bit1=1 (Dec)
                mode_str = "DEC"

            kb = list(k.to_bytes(8, 'little'))
            ib = list(input_val.to_bytes(4, 'little'))

            #zámek aby jen jedno vlákno kontrolovalo i2c sběrnici
            async with bus_lock:
                # 1. zápis konfigurace
                await i2c.write(I2C_ADDR, [0x00] + kb) # klíč
                await i2c.write(I2C_ADDR, [0x08] + ib) # data
                
                # 2. reset jádra & load dat (Start=1)
                await i2c.write(I2C_ADDR, [0x0C, cmd_load])
                
                # 3. spuštění výpočtu (Start=0), Mode musí zůstat stejný!
                await i2c.write(I2C_ADDR, [0x0C, cmd_run])
                
                # 4. Čekání (Decryption trvá déle kvůli pre-compute)
                await Timer(3, unit="us")
                
                # 5. Čtení výsledku
                await i2c.write(I2C_ADDR, [0x10])
                rb = await i2c.read(I2C_ADDR, 4)
            
            val = int.from_bytes(rb, 'little')
            
            #vyhodnocení výsledků
            if val != exp:
                raise Exception(f"[T{thread_id}] {mode_str} FAIL! Exp: {hex(exp)}, Got: {hex(val)}")
            
            if i % 2 == 0:
                dut._log.info(f"[T{thread_id}] Iter {i} {mode_str} OK")

    tasks = [cocotb.start_soon(stress_worker(t)) for t in range(NUM_THREADS)]
    await Combine(*tasks)
            
    dut._log.info("Prošlo to...díky vesmíre")