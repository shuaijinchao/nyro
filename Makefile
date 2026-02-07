UNAME            ?= $(shell uname)
REMOVE           ?= rm -rf
NYRO_DIR       ?= /usr/local/nyro

# Rockspec file
ROCKSPEC         := rockspec/nyro-master-0.rockspec

# Router engine library
ROUTER_LIB_DIR   := deps/nyro
ifeq ($(UNAME), Darwin)
    ROUTER_LIB   := libnyro_router.dylib
else
    ROUTER_LIB   := libnyro_router.so
endif

# Detect OpenResty LuaJIT path
ifeq ($(UNAME), Darwin)
	# macOS with Homebrew OpenResty
	LUAJIT_DIR       ?= $(shell test -d /opt/homebrew/opt/openresty/luajit && echo /opt/homebrew/opt/openresty/luajit || echo /usr/local/opt/openresty/luajit)
	LUAROCKS_FLAGS   := --lua-dir=$(LUAJIT_DIR)
else
	# Linux
	LUAJIT_DIR       ?= /usr/local/openresty/luajit
	ifneq ("$(wildcard $(LUAJIT_DIR))","")
		LUAROCKS_FLAGS := --lua-dir=$(LUAJIT_DIR)
	else
		LUAROCKS_FLAGS :=
	endif
endif

.PHONY: install
install:
	@echo "Building nyro_router C library..."
	cd $(ROUTER_LIB_DIR) && make
	@echo "Installing nyro_router library to system..."
	cd $(ROUTER_LIB_DIR) && make install
	@echo "Installing NYRO using luarocks..."
	@echo "Using Lua/LuaJIT at: $(LUAJIT_DIR)"
	luarocks make $(ROCKSPEC) --tree=$(NYRO_DIR) $(LUAROCKS_FLAGS)
	@echo "Installing binary and configuration files..."
	@mkdir -p $(NYRO_DIR)/bin
	@mkdir -p $(NYRO_DIR)/lib
	@install -m 755 bin/nyro $(NYRO_DIR)/bin/nyro
	@install -m 644 conf/nyro.yaml $(NYRO_DIR)/conf/nyro.yaml
	@install -m 644 conf/config.yaml $(NYRO_DIR)/conf/config.yaml
	@cp $(ROUTER_LIB_DIR)/$(ROUTER_LIB) $(NYRO_DIR)/lib/
	@echo ""
	@echo "✅ Installation complete!"
	@echo ""
	@echo "NYRO modules installed to: $(NYRO_DIR)/share/lua/5.1/"
	@echo "NYRO dependencies installed to: $(NYRO_DIR)/lib/lua/5.1/"
	@echo "Router engine installed to: $(NYRO_DIR)/lib/$(ROUTER_LIB)"
	@echo "Binary installed to: $(NYRO_DIR)/bin/nyro"
	@echo "Configuration files installed to: $(NYRO_DIR)/conf/"
	@echo ""
	@echo "To use NYRO, add to your PATH:"
	@echo "  export PATH=$(NYRO_DIR)/bin:\$$PATH"
	@echo ""
	@echo "Then you can run:"
	@echo "  nyro version"
	@echo "  nyro start"

.PHONY: dev
dev:
	@echo "Building nyro_router C library..."
	cd $(ROUTER_LIB_DIR) && make
	@echo "Installing nyro_router library for development..."
	cd $(ROUTER_LIB_DIR) && make dev
	@echo "Installing NYRO for development..."
	@echo "Using Lua/LuaJIT at: $(LUAJIT_DIR)"
	luarocks make $(ROCKSPEC) --tree=./lua_modules $(LUAROCKS_FLAGS)
	@echo ""
	@echo "✅ Development installation complete!"
	@echo ""
	@echo "You can now run NYRO directly:"
	@echo "  ./bin/nyro version"
	@echo "  ./bin/nyro start"
	@echo ""
	@echo "Note: The CLI automatically detects ./lua_modules/ and adds it to the search path."
	@echo "      Router engine library is at: ./lua_modules/lib/$(ROUTER_LIB)"

.PHONY: uninstall
uninstall:
	@echo "Uninstalling NYRO..."
	luarocks remove nyro --tree=$(NYRO_DIR) 2>/dev/null || true
	@echo "Removing binary and configuration files..."
	@$(REMOVE) $(NYRO_DIR)/bin/nyro
	@$(REMOVE) $(NYRO_DIR)/conf
	@$(REMOVE) $(NYRO_DIR)/lib/$(ROUTER_LIB)
	@echo "NYRO has been uninstalled."

.PHONY: clean
clean:
	@echo "Cleaning nyro_router build files..."
	cd $(ROUTER_LIB_DIR) && make clean
	@echo "Cleaning local development installation..."
	$(REMOVE) ./lua_modules
	@echo "Clean complete!"

.PHONY: help
help:
	@echo "NYRO Makefile targets:"
	@echo ""
	@echo "  make install     - Build C library and install NYRO to $(NYRO_DIR)"
	@echo "  make dev         - Build C library and install for local development"
	@echo "  make uninstall   - Uninstall NYRO from $(NYRO_DIR)"
	@echo "  make clean       - Clean all build files and local installation"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  NYRO_DIR       - Installation directory (default: /usr/local/nyro)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make dev"
	@echo "  make install NYRO_DIR=/opt/nyro"
	@echo "  make install NYRO_DIR=/usr/local/openresty/site"
