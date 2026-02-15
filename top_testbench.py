import cocotb
import random
from cocotb.clock import Clock
# Přidali jsme Lock (pro synchronizaci sběrnice) a Combine (pro čekání na všechna vlákna)
from cocotb.triggers import Timer, RisingEdge, Lock, Combine 

# Import profesionálního I2C Mastera
from cocotbext.i2c import I2cMaster

# ==============================================================================
# 1. REFERENČNÍ MODEL (SIMON 32/64)
# ==============================================================================
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

# ==============================================================================
# 2. TESTBENCH POMOCÍ COCOTBEXT-I2C (MULTITHREADED)
# ==============================================================================

I2C_ADDR = 0x50 

@cocotb.test()
async def test_simon_massive_multithreaded(dut):
    """
    Multithreaded ověření: 12 vláken generuje zátěž na I2C sběrnici.
    """
    
    # 1. Spuštění hodin (100 MHz)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    
    # 2. Inicializace I2C Mastera
    i2c = I2cMaster(sda=dut.sda_pin, scl=dut.scl_pin, speed=100e3)

    # --- aby máster nebombil silnou jedničku (oprava trvala cca 4 hodiny než jsem na to přišel)---
    def open_drain_sda(val):
        dut.sda_master_en.value = 1 if val else 0

    def open_drain_scl(val):
        dut.scl_master_en.value = 1 if val else 0

    i2c._set_sda = open_drain_sda
    i2c._set_scl = open_drain_scl
    
    dut._log.info("--- RESET ---")
    dut.rst.value = 1
    await Timer(100, unit="ns")
    dut.rst.value = 0
    await Timer(1000, unit="ns")
    
    # --------------------------------------------------------------------------
    # PŘÍPRAVA NA MULTITHREADING
    # --------------------------------------------------------------------------
    
    # Sanity Check - Bus Scan (Provedeme jednou před spuštěním vláken)
    dut._log.info("--- PRE-FLIGHT CHECK: Bus Scan ---")
    try:
        await i2c.read(I2C_ADDR, 1)
        dut._log.info(f"✅ Zařízení nalezeno.")
    except Exception as e:
        dut._log.error(f"❌ Zařízení neodpovídá!")
        raise e

    # Zámek pro I2C sběrnici.
    # Toto je kritické: Zajistí, že když jedno vlákno zapisuje Klíč a Data,
    # žádné jiné vlákno mu do toho neskočí, dokud není hotový Read.
    bus_lock = Lock()

    # Počet vláken a iterací
    NUM_THREADS = 12
    ITERS_PER_THREAD = 1

    dut._log.info(f"--- STARTING {NUM_THREADS} THREADS ({ITERS_PER_THREAD} iters each) ---")

    # Definice Worker Funkce (jedno vlákno)
    async def stress_worker(thread_id):
        for i in range(ITERS_PER_THREAD):
            # 1. Generování dat (běží paralelně, neblokuje sběrnici)
            k = random.getrandbits(64)
            p = random.getrandbits(32)
            exp = simon_32_64_gold(p, k)
            
            kb = list(k.to_bytes(8, 'little'))
            pb = list(p.to_bytes(4, 'little'))

            # 2. KRITICKÁ SEKCE - Přístup k I2C
            # Musíme zamknout celou sekvenci operací, protože Simon má stavové registry.
            async with bus_lock:
                # Zápis Key (0x00)
                await i2c.write(I2C_ADDR, [0x00] + kb)
                # Zápis Plaintext (0x08)
                await i2c.write(I2C_ADDR, [0x08] + pb)
                # Start (0x0C)
                await i2c.write(I2C_ADDR, [0x0C, 0x01])
                
                # Čekání na výpočet HW
                await Timer(2, unit="us")
                
                # Čtení výsledku (0x10)
                await i2c.write(I2C_ADDR, [0x10])
                rb = await i2c.read(I2C_ADDR, 4)
            
            # 3. Vyhodnocení (mimo zámek, uvolníme sběrnici co nejdříve)
            val = int.from_bytes(rb, 'little')
            
            if val != exp:
                dut._log.error(f"[T{thread_id}] Iter {i} FAILED")
                dut._log.error(f"Key: {hex(k)}")
                dut._log.error(f"Plain: {hex(p)}")
                dut._log.error(f"Exp: {hex(exp)}")
                dut._log.error(f"Got: {hex(val)}")
                raise Exception(f"Thread {thread_id} Failed at iter {i}")
            
            # Logujeme jen občas, ať nezahltíme konzoli
            if i % 50 == 0:
                dut._log.info(f"[T{thread_id}] Iter {i} OK")

        dut._log.info(f"✅ [T{thread_id}] DONE")

    # --------------------------------------------------------------------------
    # SPUŠTĚNÍ VLÁKEN
    # --------------------------------------------------------------------------
    tasks = []
    for t in range(NUM_THREADS):
        # start_soon spustí "vlákno" (coroutinu)
        tasks.append(cocotb.start_soon(stress_worker(t)))

    # Čekáme, až všech 12 vláken skončí
    await Combine(*tasks)
            
    dut._log.info("🎉🎉🎉 MULTITHREADED TEST COMPLETE - ALL PASSED 🎉🎉🎉")