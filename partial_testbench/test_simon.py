import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


def rotl(x, k):
    return ((x << k) & 0xFFFF) | (x >> (16 - k))

def rotr(x, k):
    return ((x >> k) & 0xFFFF) | ((x << (16 - k)) & 0xFFFF)

def simon_32_64_gold(plaintext_int, key_int):
    key = [
        (key_int >> 0) & 0xFFFF,  # k0
        (key_int >> 16) & 0xFFFF, # k1
        (key_int >> 32) & 0xFFFF, # k2
        (key_int >> 48) & 0xFFFF  # k3
    ]

    L = (plaintext_int >> 16) & 0xFFFF
    R = (plaintext_int >> 0) & 0xFFFF

    z0 = 0b11111010001001010110000111001101111101000100101011000011100110
#feistalova funkce pro simon (32 opakování) viz. simon dokumentace
    for i in range(32):
        curr_k = key[0]
        f_val = (rotl(L, 1) & rotl(L, 8)) ^ rotl(L, 2)
        
        new_L = R ^ f_val ^ curr_k
        new_R = L
        L = new_L
        R = new_R
        c = 0xFFFC
        z_bit = (z0 >> (61 - i)) & 1
        tmp = rotr(key[3], 3) ^ key[1]
        tmp_ror1 = rotr(tmp, 1)
        k_new = c ^ z_bit ^ key[0] ^ tmp ^ tmp_ror1
        key = key[1:] + [k_new]

    return (L << 16) | R


#test 1 ověřený vektor
@cocotb.test()
async def simon_basic_test(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut._log.info("--- START: Basic NSA Vector Test ---")
    
    # reset
    dut.rst.value = 1
    dut.block.value = 0
    dut.key.value = 0
    await ClockCycles(dut.clk, 2)
    
    # vstupy (NSA testovací vektor pro Simon32/64)
    test_key = 0x1918111009080100
    test_block = 0x65656877
    expected = 0xc69be9bb
    
    dut.key.value = test_key
    dut.block.value = test_block
    
    # start
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    
    # čekej
    await RisingEdge(dut.done)
    await RisingEdge(dut.clk)
    
    #výsledel
    res = int(dut.ciphertext.value)
    
    if res == expected:
        dut._log.info(f"PASS: {res:08x} matches NSA vektor.")
    else:
        dut._log.error(f"FAIL: {res:08x} != {expected:08x}")
        raise 

#test 2 random
@cocotb.test()
async def simon_random_stress_test(dut):
    
    NUM_TESTS = 5000  # počet random vektorů
    
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut._log.info(f"--- START: Random Stress Test ({NUM_TESTS} rounds) ---")

    for i in range(NUM_TESTS):
        # náhodný vstup
        key_rand = random.getrandbits(64)
        block_rand = random.getrandbits(32)
        
        # výpočet python modelem
        expected_python = simon_32_64_gold(block_rand, key_rand)
        
        #simulace verilogem

        # reset
        dut.rst.value = 1
        await ClockCycles(dut.clk, 2) 
        
        # vstupy random
        dut.key.value = key_rand
        dut.block.value = block_rand
        
        # start
        await RisingEdge(dut.clk)
        dut.rst.value = 0
        
        # čekej
        await RisingEdge(dut.done)
        await RisingEdge(dut.clk)
        
        #výsledek
        res_verilog = int(dut.ciphertext.value)
        
        # porovnání python a verilog výsledků
        if res_verilog != expected_python:
            dut._log.error(f"ERR IN ITERATION {i}!")
            dut._log.error(f"Input Block: {block_rand:08x}")
            dut._log.error(f"Input Key:   {key_rand:016x}")
            dut._log.error(f"Verilog:     {res_verilog:08x}")
            dut._log.error(f"Python:      {expected_python:08x}")
            raise Exception("!MISMATCH!")
        
        # logování každý 10. test
        if i % 10 == 0:
            dut._log.info(f"Iteration {i}/{NUM_TESTS} OK. (Verilog {res_verilog:08x} == Py {expected_python:08x})")

    dut._log.info(f"ALL TEST ({NUM_TESTS}) SUCCESSFULL!")

#test 3