# Makefile
SHELL := bash

CRYSTAL = crystal clear_cache && crystal run --error-trace 
TC = \e[4;33m

banner = @echo -e "\n$(TC)== $(1) ==\e[0m\n"

define run_test
	$(call banner,TEST - CTTY)
	@$(CRYSTAL) spec/ctty_test.cr

	$(call banner,TEST - JOB CONTROL)
	@$(CRYSTAL) spec/jobcontrol_test.cr
endef

.PHONY: all test

all: test

test:
	$(run_test)
