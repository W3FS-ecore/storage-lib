SHELL=/usr/bin/env bash

all: build
.PHONY: all

unexport GOFLAGS

GOCC?=go

GOVERSION:=$(shell $(GOCC) version | tr ' ' '\n' | grep go1 | sed 's/^go//' | awk -F. '{printf "%d%03d%03d", $$1, $$2, $$3}')
ifeq ($(shell expr $(GOVERSION) \< 1016000), 1)
$(warning Your Golang version is go$(shell expr $(GOVERSION) / 1000000).$(shell expr $(GOVERSION) % 1000000 / 1000).$(shell expr $(GOVERSION) % 1000))
$(error Update Golang to version to at least 1.16.0)
endif

# git modules that need to be loaded
MODULES:=

CLEAN:=
BINS:=

ldflags=-X=github.com/filecoin-project/lotus/build.CurrentCommit=+git.$(subst -,.,$(shell git describe --always --match=NeVeRmAtCh --dirty 2>/dev/null || git rev-parse --short HEAD 2>/dev/null))
ifneq ($(strip $(LDFLAGS)),)
	ldflags+=-extldflags=$(LDFLAGS)
endif

GOFLAGS+=-ldflags="$(ldflags)"
GOFLAGS+=-tags=debug


## FFI

FFI_PATH:=extern/filecoin-ffi/
FFI_DEPS:=.install-filcrypto
FFI_DEPS:=$(addprefix $(FFI_PATH),$(FFI_DEPS))

$(FFI_DEPS): build/.filecoin-install ;

build/.filecoin-install: $(FFI_PATH)
	$(MAKE) -C $(FFI_PATH) $(FFI_DEPS:$(FFI_PATH)%=%)
	@touch $@

MODULES+=$(FFI_PATH)
BUILD_DEPS+=build/.filecoin-install
CLEAN+=build/.filecoin-install

ffi-version-check:
	@[[ "$$(awk '/const Version/{print $$5}' extern/filecoin-ffi/version.go)" -eq 3 ]] || (echo "FFI version mismatch, update submodules"; exit 1)
BUILD_DEPS+=ffi-version-check

.PHONY: ffi-version-check

# $(MODULES): build/.update-modules ;
# dummy file that marks the last time modules were updated
# build/.update-modules:
# 	git submodule update --init --recursive
# 	touch $@

# end git modules

## MAIN BINARIES

# CLEAN+=build/.update-modules

deps: $(BUILD_DEPS)
.PHONY: deps

#build-devnets: build lotus-seed lotus-shed lotus-wallet lotus-gateway
#.PHONY: build-devnets

w3fs-worker: $(BUILD_DEPS)
	rm -f w3fs-worker
	$(GOCC) build $(GOFLAGS) -o w3fs-worker ./cmd/lotus-seal-worker
.PHONY: w3fs-worker
BINS+=w3fs-worker

w3fs-fetch: $(BUILD_DEPS)
	rm -f w3fs-fetch
	$(GOCC) build $(GOFLAGS) -o w3fs-fetch ./cmd/lotus

.PHONY: w3fs-fetch
BINS+=w3fs-fetch

build: w3fs-fetch w3fs-worker w3fs-bench
	@[[ $$(type -P "w3fs-worker") ]] && echo "Caution: you have \
an existing w3fs-fetch binary in your PATH. This may cause problems if you don't run 'sudo make install'" || true

.PHONY: build

#install: install-daemon install-miner install-worker
install: install-fetch install-worker install-bench


install-worker:
	install -C ./w3fs-worker /usr/local/bin/w3fs-worker

install-bench:
	install -C ./w3fs-bench /usr/local/bin/w3fs-bench

install-fetch:
	install -C ./w3fs-fetch /usr/local/bin/w3fs-fetch

uninstall:
	rm /usr/local/bin/w3fs-worker /usr/local/bin/w3fs-bench /usr/local/bin/w3fs-fetch

w3fs-bench:
	rm -f w3fs-bench
	$(GOCC) build -o w3fs-bench ./cmd/lotus-bench
.PHONY: w3fs-bench
BINS+=w3fs-bench


buildall: $(BINS)


clean:
	rm -rf $(CLEAN) $(BINS)
	-$(MAKE) -C $(FFI_PATH) clean
.PHONY: clean

dist-clean:
	git clean -xdff
	git submodule deinit --all -f
.PHONY: dist-clean

print-%:
	@echo $*=$($*)
