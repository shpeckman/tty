# Makefile
CRYSTAL ?= crystal
EXT_DIR := src/ext
EXT_OBJ := $(EXT_DIR)/tty_syscall.o
EXT_SRC := $(EXT_DIR)/tty_syscall.s

.PHONY: all ext spec clean

all: ext

ext: $(EXT_OBJ)

$(EXT_OBJ): $(EXT_SRC)
	cc -c -o $@ $<

spec: ext
	$(CRYSTAL) spec

clean:
	rm -f $(EXT_OBJ)
