# Makefile
CRYSTAL ?= crystal
EXAMPLE_DIR := .build/examples
EXAMPLE_SRC := $(wildcard examples/*.cr)
EXAMPLE_BIN := $(patsubst examples/%.cr,$(EXAMPLE_DIR)/%,$(EXAMPLE_SRC))

.PHONY: all spec examples clean

all: spec

spec:
	$(CRYSTAL) spec

examples: $(EXAMPLE_BIN)

$(EXAMPLE_DIR)/%: examples/%.cr
	mkdir -p $(EXAMPLE_DIR)
	$(CRYSTAL) build $< -o $@

clean:
	rm -rf .build
