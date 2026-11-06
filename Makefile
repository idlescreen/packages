OODA_COMPILER ?= $(shell command -v oodac 2>/dev/null || echo /Projects/openOODA-core/oodac/bin/oodac)
BIN := bin/packages
TESTBIN := bin/test_packages
SRC := main.oo $(wildcard src/*.oo)

.PHONY: all build verify test det clean

all: build verify test det

build: $(BIN)
	@cp -f $(BIN) bin/prune
	@cp -f $(BIN) bin/update
	@cp -f $(BIN) bin/sign
	@cp -f $(BIN) bin/install
	@cp -f $(BIN) bin/sync-hashes
	@chmod +x bin/packages bin/prune bin/update bin/sign bin/install bin/sync-hashes

$(BIN): $(SRC)
	@mkdir -p bin .ooda-cache
	@$(OODA_COMPILER) build main.oo -o $(BIN)

verify:
	@/Projects/openOODA-agents/oohat/lint-oo-size $(CURDIR)

test: build
	@mkdir -p .ooda-cache
	@$(OODA_COMPILER) build tests/test_main.oo -o $(TESTBIN)
	@./$(TESTBIN)
	@rm -f $(TESTBIN)
	@./bin/packages --self-test
	@./bin/prune --dry-run > /dev/null
	@./bin/install --dry-run > /dev/null
	@./bin/sync-hashes --check
	@echo "PASS: all idlescreen-packages tests"

det: build
	@mkdir -p .ooda-cache
	@$(OODA_COMPILER) build main.oo -o .ooda-cache/det_a > /dev/null
	@$(OODA_COMPILER) build main.oo -o .ooda-cache/det_b > /dev/null
	@cmp -s .ooda-cache/det_a .ooda-cache/det_b && rm -rf .ooda-cache && echo "PASS: deterministic build (byte-identical)"

clean:
	@rm -rf .ooda-cache $(TESTBIN)
