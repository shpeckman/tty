# Makefile
CRYSTAL ?= crystal
EXT_DIR := src/ext
EXT_OBJ := $(EXT_DIR)/tty_syscall.o
EXT_SRC := $(EXT_DIR)/tty_syscall.s
EXAMPLE_DIR := .build/examples
EXAMPLE_SRC := $(wildcard examples/*.cr)
EXAMPLE_BIN := $(patsubst examples/%.cr,$(EXAMPLE_DIR)/%,$(EXAMPLE_SRC))

.PHONY: all ext spec examples clean

all: ext

ext: $(EXT_OBJ)

$(EXT_OBJ): $(EXT_SRC)
	cc -c -o $@ $<

spec: ext
	$(CRYSTAL) spec

examples: ext $(EXAMPLE_BIN)

$(EXAMPLE_DIR)/%: examples/%.cr $(EXT_OBJ)
	mkdir -p $(EXAMPLE_DIR)
	$(CRYSTAL) build $< -o $@

clean:
	rm -f $(EXT_OBJ)
	rm -rf .build
