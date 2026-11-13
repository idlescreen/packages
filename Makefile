OOHAT ?= /Projects/openOODA-agents/oohat/lint-oo-size
# The compiler follows OODA_HOME so a CI runner that stages the toolchain
# under /tmp resolves the same path the developer checkout does.
OODA_COMPILER ?= $(shell command -v oodac 2>/dev/null || echo $(OODA_HOME)/oodac/bin/oodac)
# The compiler resolves oostd/... imports through OODA_STD_DIR. Its own
# upward walk from the source tree is disabled under /tmp, so a CI tree
# staged in /tmp has to pass the std path explicitly.
OODA_HOME ?= $(shell if [ -x "$$HOME/.openooda/bin/oodac" ]; then echo "$$HOME/.openooda"; elif [ -d "$$HOME/Projects/openOODA-core/oodac" ]; then echo "$$HOME/Projects/openOODA-core"; elif [ -d /Projects/openOODA-core/oodac ]; then echo /Projects/openOODA-core; else echo "$(abspath $(CURDIR)/../../openOODA-core)"; fi)
OODA_STD_DIR ?= $(shell d=$(CURDIR); while [ "$$d" != "/" ]; do if [ -d "$$d/oostd" ]; then echo "$$d/oostd"; break; fi; d=$$(dirname $$d); done)
OODA_READDIR ?= $(CURDIR):$(OODA_HOME)$(if $(OODA_STD_DIR),:$(OODA_STD_DIR))
OODA_WRITEDIR ?= $(CURDIR):/tmp
OO_LIST_AMBIENT_QUOTA ?= 8589934592
ENV := OO_LIST_AMBIENT_QUOTA=$(OO_LIST_AMBIENT_QUOTA) OODA_FS_READDIR=$(OODA_READDIR) OODA_FS_WRITEDIR=$(OODA_WRITEDIR) OODA_COMPILER=$(OODA_COMPILER) OODAC_BIN=$(OODA_COMPILER) OODA_STD_DIR=$(OODA_STD_DIR)
BIN := bin/packages
TESTBIN := bin/test_packages
SRC := main.oo $(wildcard src/*.oo)
VER := 5.0.2

.PHONY: all build verify test det clean std-check check

all: build verify test det

build: $(BIN)
	@cp -f $(BIN) bin/prune
	@cp -f $(BIN) bin/update
	@cp -f $(BIN) bin/sign
	@cp -f $(BIN) bin/install
	@cp -f $(BIN) bin/sync-hashes
	@chmod +x bin/packages bin/prune bin/update bin/sign bin/install bin/sync-hashes

std-check:
	@test -n "$(OODA_STD_DIR)" || { echo "FAIL: no std repo named oostd in any ancestor of $(CURDIR)"; \
		echo "      clone openOODA-core/std as \`oostd\` beside this project"; exit 1; }
	@echo "PASS: std repo at $(OODA_STD_DIR)"

# The compiler's own typecheck over every page. Without it a page that no
# other page imports stays invisible until something links it.
check:
	@mkdir -p .ooda-cache
	@for f in $$(find . -name "*.oo" -not -path "./.git/*" -not -path "./bin/*" -not -path "./.ooda-cache/*"); do \
		$(ENV) $(OODA_COMPILER) check "$$f" > .ooda-cache/check_out.txt 2>&1 || { echo "VIOLATION: oodac check fails on $$f"; echo "--- compiler output ---"; cat .ooda-cache/check_out.txt; exit 1; } \
	done; \
	echo "PASS: oodac check holds on all .oo files"

$(BIN): $(SRC)
	@mkdir -p bin .ooda-cache
	@$(MAKE) --no-print-directory std-check
	@$(ENV) $(OODA_COMPILER) build main.oo -o $(BIN)

verify: check
	@if [ -x "$(OOHAT)" ]; then $(OOHAT) $(CURDIR); \
	else echo "SKIP: page-rule linter not found at $(OOHAT) — set OOHAT to run it"; fi

test: build
	@mkdir -p .ooda-cache
	@$(ENV) $(OODA_COMPILER) build tests/test_main.oo -o $(TESTBIN)
	@./$(TESTBIN)
	@rm -f $(TESTBIN)
	@./bin/packages --self-test
	@./bin/packages --version | grep -q "$(VER)" && echo "PASS: --version $(VER)"
	@./bin/packages --self-test | grep -q "$(VER)" && echo "PASS: --self-test $(VER)"
	@./bin/packages prune --dry-run > /dev/null && echo "PASS: prune (verb form)"
	@./bin/packages install --dry-run > /dev/null && echo "PASS: install (verb form)"
	@./bin/packages sync-hashes --check && echo "PASS: sync-hashes (verb form)"
	@./bin/prune --dry-run > /dev/null && ./bin/install --dry-run > /dev/null && ./bin/sync-hashes --check \
		&& echo "PASS: multi-call alias dispatch"
	@echo "PASS: all idlescreen-packages tests"

det: build
	@mkdir -p .ooda-cache
	@$(ENV) $(OODA_COMPILER) build main.oo -o .ooda-cache/det_a > /dev/null
	@$(ENV) $(OODA_COMPILER) build main.oo -o .ooda-cache/det_b > /dev/null
	@cmp -s .ooda-cache/det_a .ooda-cache/det_b && rm -rf .ooda-cache && echo "PASS: deterministic build (byte-identical)"

clean:
	@rm -rf .ooda-cache $(TESTBIN)
