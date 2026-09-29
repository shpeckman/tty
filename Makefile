# Makefile
CRYSTAL ?= crystal
EXAMPLE_SRC := $(wildcard examples/*.cr)

.PHONY: all spec examples clean

all: spec

spec:
	$(CRYSTAL) spec

examples:
	@for example in $(EXAMPLE_SRC); do \
		echo "==> $$example"; \
		$(CRYSTAL) run $$example; \
	done

clean:
	rm -rf .build
