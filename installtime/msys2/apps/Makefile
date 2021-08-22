# Minimal makefile just for installation time
.PHONY: all
all:

.PHONY: show-vcvars-dev
show-vcvars-dev:
	@if [ "$$MSYSTEM" = MSYS ] || [ -e /usr/bin/cygpath ]; then \
		if [ `/usr/bin/uname -m` = x86_64 ]; then v=vcvars64; else v=vcvar32; fi; \
	else \
		v=notapplicable; \
	fi && \
	if [ -z "$(OUT_VCVARS_BAT)" ]; then \
		echo $$v; \
	else \
		echo $$v > "$(OUT_VCVARS_BAT)"; \
	fi
