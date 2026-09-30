# Makefile
CRYSTAL ?= crystal
EXAMPLE_SRC := $(wildcard examples/*.cr)
BENCH_SRC := $(wildcard benchmarks/*.cr)

.PHONY: all spec examples bench clean

all: spec

spec:
	$(CRYSTAL) spec

examples:
	@for example in $(EXAMPLE_SRC); do \
		echo "==> $$example"; \
		$(CRYSTAL) run $$example; \
	done

bench:
	@for bench in $(BENCH_SRC); do \
		echo "==> $$bench"; \
		$(CRYSTAL) run --release $$bench; \
	done

clean:
	rm -rf .build
