# Makefile pro Cocotb a Icarus Verilog

# Výchozí simulátor
SIM ?= icarus

# Jazyk top level modulu
TOPLEVEL_LANG ?= verilog

# Cesty k Verilog souborům (PWD je aktuální složka)
VERILOG_SOURCES += $(PWD)/simon_key.v
VERILOG_SOURCES += $(PWD)/simon_rounds.v

# Název TOP modulu ve Verilogu (to je ten, co má porty clk, rst, key...)
TOPLEVEL = simon_rounds

# Název Python souboru s testem (bez .py)
MODULE = test_simon

# Zahrnutí standardních pravidel Cocotb
include $(shell cocotb-config --makefiles)/Makefile.sim