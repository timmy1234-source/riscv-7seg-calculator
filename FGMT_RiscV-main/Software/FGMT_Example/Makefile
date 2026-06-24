#-----------------------------------------------------------------------------------------------
#-- FGMT-RiscV: Implementation of 32-Bit Risc-V allowing fine grained multiprocessing
#-- Copyright (C) 2025  Bernhard Lang
#--
#-- This program is free software; you can redistribute it and/or modify
#-- it under the terms of the GNU General Public License as published by
#-- the Free Software Foundation; either version 3 of the License, or
#-- (at your option) any later version.
#--
#-- This program is distributed in the hope that it will be useful,
#-- but WITHOUT ANY WARRANTY; without even the implied warranty of
#-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#-- GNU General Public License for more details.
#--
#-- You should have received a copy of the GNU General Public License
#-- along with this program; if not, see http://www.gnu.org/licenses
#-- or write to the Free Software Foundation,Inc., 51 Franklin Street,
#-- Fifth Floor, Boston, MA 02110-1301  USA
#-----------------------------------------------------------------------------------------------

#---------------------------------------------------------------
# Infos from the environment                                  
#---------------------------------------------------------------
# project name
PROJECTNAME ?= UNKNOWN
# selected configuration
CONFIGNAME  ?= NOCONFIG
# projects source directories
SOURCEDIRS  ?= scr
# projects include directories
INCDIRS     ?= inc

# Directory for object files and the final executable
BUILD_DIR = $(CONFIGNAME)
# Output Executable
TARGET = $(BUILD_DIR)/$(PROJECTNAME).elf

LINKERSCRIPT = Linker.ld

#---------------------------------------------------------------

# Compiler and Linker
CC      = riscv-none-elf-gcc
LD      = riscv-none-elf-gcc
OBJCOPY = riscv-none-elf-objcopy
OBJDUMP = riscv-none-elf-objdump

ifeq ($(CONFIGNAME),Debug)
  # Compiler and Linker Flags
  CFLAGS   = -O0 -g3 -ggdb -Wall -march=rv32i -mabi=ilp32
  CFLAGS  += $(foreach dir, $(INCDIRS), -I$(dir))
  CFLAGS  += -fstack-usage
  ASFLAGS  = -O0 -g3 -ggdb -march=rv32i -mabi=ilp32
  LDFLAGS  = -O0 -g3 -ggdb -nostartfiles -nodefaultlibs -nostdlib
  LDFLAGS += -static -Xlinker -T$(LINKERSCRIPT) -Xlinker --no-relax
  LDFLAGS += -fstack-usage
  LDLIBS   = 
else ifeq ($(CONFIGNAME),SizeOpt)
  # Compiler and Linker Flags
  CFLAGS   = -Os -Wall -march=rv32i -mabi=ilp32
  CFLAGS  += $(foreach dir, $(INCDIRS), -I$(dir))
  CFLAGS  += -fstack-usage
  ASFLAGS  = -Os -march=rv32i -mabi=ilp32
  LDFLAGS  = -nostartfiles -nodefaultlibs -nostdlib
  LDFLAGS += -static -Xlinker -TLinker.ld -Xlinker --no-relax
  LDFLAGS += -fstack-usage
  LDLIBS   = 
else
  $(error $(CONFIGNAME) ist keine gueltige Konfiguration)
endif

# OBJDUMP disassembly flags
DISASSFLAGS  = -C -h -t -j.vector_table -j.text -j.data -j.bss
DISASSFLAGS += -j.preinit_array -j.init_array -j.fini_array
# OBJDUMP info flags
INFOFLAGS    = -C -h -j.vector_table -j.text -j.data -j.bss
INFOFLAGS   += -j.preinit_array -j.init_array -j.fini_array
#---------------------------------------------------------------------

# Find all source files in the specified directories
SRC = $(foreach dir, $(SOURCEDIRS), $(wildcard $(dir)/*.c))
ASM = $(foreach dir, $(SOURCEDIRS), $(wildcard $(dir)/*.S))
ASM = $(foreach dir, $(SOURCEDIRS), $(wildcard $(dir)/*.S))

# Create object directories mirroring source directories under BUILD_DIR
OBJ_DIRS  = $(BUILD_DIR)
OBJ_DIRS += $(foreach dir, $(SOURCEDIRS), $(BUILD_DIR)/$(dir))

# Generate the respective object file paths in the Debug directory
OBJ = $(patsubst %.c, $(BUILD_DIR)/%.o, $(SRC))
OBJ += $(patsubst %.S, $(BUILD_DIR)/%.o, $(ASM))

# Default Target
all: $(TARGET)

# Linking with a prerequisite on directories
$(TARGET): $(OBJ) | $(LINKERSCRIPT) $(OBJ_DIRS) 
	$(LD) $(LDFLAGS) -o $@ $^ $(LDLIBS)
	$(OBJCOPY) -O ihex $@ $(BUILD_DIR)/$(PROJECTNAME).hex
	$(OBJDUMP) $(DISASSFLAGS) -S $@ > $(BUILD_DIR)/$(PROJECTNAME)_diss.txt 
	$(OBJDUMP) $(INFOFLAGS) $@

# C source to object, with prerequisite on directories
$(BUILD_DIR)/%.o: %.c | $(OBJ_DIRS)
	$(CC) $(CFLAGS) -c $< -o $@

# Assembly to object, with a prerequisite on directories
$(BUILD_DIR)/%.o: %.S | $(OBJ_DIRS)
	$(CC) $(CFLAGS) -c $< -o $@

# A rule to create necessary object directories
$(BUILD_DIR):
	mkdir -p $(OBJ_DIRS)

# Clean Target
clean:
	rm -rf $(BUILD_DIR)

# Phony Targets
.PHONY: all clean $(OBJ_DIRS)
