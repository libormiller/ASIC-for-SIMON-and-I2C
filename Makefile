# makefile pro simon_top s I2C testbenchem

# výchozí simulátor
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# zdrojové soubory 
VERILOG_SOURCES += $(PWD)/simon_key.v
VERILOG_SOURCES += $(PWD)/simon_rounds.v
VERILOG_SOURCES += $(PWD)/i2c_slave.v
VERILOG_SOURCES += $(PWD)/simon_top.v

# topmodul verilogu
TOPLEVEL = simon_top

# python test
MODULE = top_testbench

# cocotb pravidla
include $(shell cocotb-config --makefiles)/Makefile.sim