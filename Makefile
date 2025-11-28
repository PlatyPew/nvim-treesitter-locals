NVIM_VERSION ?= nightly
LUALS_VERSION := 3.15.0

DEPDIR ?= .test-deps
CURL ?= curl -sL --create-dirs

ifeq ($(shell uname -s),Darwin)
    NVIM_ARCH ?= macos-arm64
    LUALS_ARCH ?= darwin-arm64
    STYLUA_ARCH ?= macos-aarch64
    RUST_ARCH ?= aarch64-apple-darwin
else
    NVIM_ARCH ?= linux-x86_64
    LUALS_ARCH ?= linux-x64
    STYLUA_ARCH ?= linux-x86_64
    RUST_ARCH ?= x86_64-unknown-linux-gnu
endif

.DEFAULT_GOAL := all

# download test dependencies

NVIM := $(DEPDIR)/nvim-$(NVIM_ARCH)
NVIM_TARBALL := $(NVIM).tar.gz
NVIM_URL := https://github.com/neovim/neovim/releases/download/$(NVIM_VERSION)/$(notdir $(NVIM_TARBALL))
NVIM_BIN := $(NVIM)/nvim-$(NVIM_ARCH)/bin/nvim
NVIM_RUNTIME=$(NVIM)/nvim-$(NVIM_ARCH)/share/nvim/runtime

.PHONY: nvim
nvim: $(NVIM)

$(NVIM):
	$(CURL) $(NVIM_URL) -o $(NVIM_TARBALL)
	mkdir $@
	tar -xf $(NVIM_TARBALL) -C $@
	rm -rf $(NVIM_TARBALL)

LUALS := $(DEPDIR)/lua-language-server-$(LUALS_VERSION)-$(LUALS_ARCH)
LUALS_TARBALL := $(LUALS).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(notdir $(LUALS_TARBALL))

.PHONY: luals
luals: $(LUALS)

$(LUALS):
	$(CURL) $(LUALS_URL) -o $(LUALS_TARBALL)
	mkdir $@
	tar -xf $(LUALS_TARBALL) -C $@
	rm -rf $(LUALS_TARBALL)

STYLUA := $(DEPDIR)/stylua-$(STYLUA_ARCH)
STYLUA_TARBALL := $(STYLUA).zip
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/latest/download/$(notdir $(STYLUA_TARBALL))

.PHONY: stylua
stylua: $(STYLUA)

$(STYLUA):
	$(CURL) $(STYLUA_URL) -o $(STYLUA_TARBALL)
	unzip $(STYLUA_TARBALL) -d $(STYLUA)
	rm -rf $(STYLUA_TARBALL)

PLENARY := $(DEPDIR)/plenary.nvim

.PHONY: plenary
plenary: $(PLENARY)

$(PLENARY):
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $(PLENARY)

# actual test targets

.PHONY: lua
lua: formatlua checklua

.PHONY: formatlua
formatlua: $(STYLUA)
	$(STYLUA)/stylua .

.PHONY: checklua
checklua: $(LUALS) $(NVIM)
	VIMRUNTIME=$(NVIM_RUNTIME) $(LUALS)/bin/lua-language-server \
		--configpath=../.luarc.json \
		--check=./

.PHONY: tests
tests: $(NVIM)  $(PLENARY)
		PLENARY=$(PLENARY) $(NVIM_BIN) --headless --clean -u scripts/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/$(TESTS) { minimal_init = './scripts/minimal_init.lua' }"

.PHONY: all
all: lua tests

.PHONY: clean
clean:
	rm -rf $(DEPDIR)
