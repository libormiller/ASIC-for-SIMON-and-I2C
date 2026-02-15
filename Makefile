# Makefile pro simon_top s I2C testbenchem

# Výchozí simulátor
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Zdrojové soubory (pořadí je důležité kvůli závislostem, pokud nepoužíváte `include`)
# Zde používáme globální wildcard nebo explicitní výčet
VERILOG_SOURCES += $(PWD)/simon_key.v
VERILOG_SOURCES += $(PWD)/simon_rounds.v
VERILOG_SOURCES += $(PWD)/i2c_slave.v
VERILOG_SOURCES += $(PWD)/simon_top.v

# Název top modulu v Verilogu
TOPLEVEL = simon_top

# Název Python souboru s testem (bez .py)
MODULE = top_testbench

# Zahrnutí pravidel Cocotb
include $(shell cocotb-config --makefiles)/Makefile.sim