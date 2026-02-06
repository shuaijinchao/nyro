UNAME            ?= $(shell uname)
REMOVE           ?= rm -rf
APIOAK_DIR       ?= /usr/local/apioak

# Rockspec file
ROCKSPEC         := rockspec/apioak-master-0.rockspec

# Router engine library
ROUTER_LIB_DIR   := deps/apioak
ifeq ($(UNAME), Darwin)
    ROUTER_LIB   := libapioak_router.dylib
else
    ROUTER_LIB   := libapioak_router.so
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
	@echo "Building apioak_router C library..."
	cd $(ROUTER_LIB_DIR) && make
	@echo "Installing apioak_router library to system..."
	cd $(ROUTER_LIB_DIR) && make install
	@echo "Installing APIOAK using luarocks..."
	@echo "Using Lua/LuaJIT at: $(LUAJIT_DIR)"
	luarocks make $(ROCKSPEC) --tree=$(APIOAK_DIR) $(LUAROCKS_FLAGS)
	@echo "Installing binary and configuration files..."
	@mkdir -p $(APIOAK_DIR)/bin
	@mkdir -p $(APIOAK_DIR)/lib
	@install -m 755 bin/apioak $(APIOAK_DIR)/bin/apioak
	@install -m 644 conf/apioak.yaml $(APIOAK_DIR)/conf/apioak.yaml
	@install -m 644 conf/config.yaml $(APIOAK_DIR)/conf/config.yaml
	@cp $(ROUTER_LIB_DIR)/$(ROUTER_LIB) $(APIOAK_DIR)/lib/
	@echo ""
	@echo "✅ Installation complete!"
	@echo ""
	@echo "APIOAK modules installed to: $(APIOAK_DIR)/share/lua/5.1/"
	@echo "APIOAK dependencies installed to: $(APIOAK_DIR)/lib/lua/5.1/"
	@echo "Router engine installed to: $(APIOAK_DIR)/lib/$(ROUTER_LIB)"
	@echo "Binary installed to: $(APIOAK_DIR)/bin/apioak"
	@echo "Configuration files installed to: $(APIOAK_DIR)/conf/"
	@echo ""
	@echo "To use APIOAK, add to your PATH:"
	@echo "  export PATH=$(APIOAK_DIR)/bin:\$$PATH"
	@echo ""
	@echo "Then you can run:"
	@echo "  apioak version"
	@echo "  apioak start"

.PHONY: dev
dev:
	@echo "Building apioak_router C library..."
	cd $(ROUTER_LIB_DIR) && make
	@echo "Installing apioak_router library for development..."
	cd $(ROUTER_LIB_DIR) && make dev
	@echo "Installing APIOAK for development..."
	@echo "Using Lua/LuaJIT at: $(LUAJIT_DIR)"
	luarocks make $(ROCKSPEC) --tree=./lua_modules $(LUAROCKS_FLAGS)
	@echo ""
	@echo "✅ Development installation complete!"
	@echo ""
	@echo "You can now run APIOAK directly:"
	@echo "  ./bin/apioak version"
	@echo "  ./bin/apioak start"
	@echo ""
	@echo "Note: The CLI automatically detects ./lua_modules/ and adds it to the search path."
	@echo "      Router engine library is at: ./lua_modules/lib/$(ROUTER_LIB)"

.PHONY: uninstall
uninstall:
	@echo "Uninstalling APIOAK..."
	luarocks remove apioak --tree=$(APIOAK_DIR) 2>/dev/null || true
	@echo "Removing binary and configuration files..."
	@$(REMOVE) $(APIOAK_DIR)/bin/apioak
	@$(REMOVE) $(APIOAK_DIR)/conf
	@$(REMOVE) $(APIOAK_DIR)/lib/$(ROUTER_LIB)
	@echo "APIOAK has been uninstalled."

.PHONY: clean
clean:
	@echo "Cleaning apioak_router build files..."
	cd $(ROUTER_LIB_DIR) && make clean
	@echo "Cleaning local development installation..."
	$(REMOVE) ./lua_modules
	@echo "Clean complete!"

.PHONY: help
help:
	@echo "APIOAK Makefile targets:"
	@echo ""
	@echo "  make install     - Build C library and install APIOAK to $(APIOAK_DIR)"
	@echo "  make dev         - Build C library and install for local development"
	@echo "  make uninstall   - Uninstall APIOAK from $(APIOAK_DIR)"
	@echo "  make clean       - Clean all build files and local installation"
	@echo "  make help        - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  APIOAK_DIR       - Installation directory (default: /usr/local/apioak)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make dev"
	@echo "  make install APIOAK_DIR=/opt/apioak"
	@echo "  make install APIOAK_DIR=/usr/local/openresty/site"
