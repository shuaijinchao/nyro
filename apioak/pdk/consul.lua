--
-- Consul Stub Module
--
-- This is a stub module for backward compatibility.
-- Consul support has been removed in favor of the Store abstraction layer.
-- This module exists only to prevent loading errors from legacy code.
--

local _M = {}

-- Stub instance that returns errors for all operations
local stub_instance = {
    get_key = function(self, key)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
    put_key = function(self, key, value, args)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
    list_keys = function(self, prefix)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
    delete_key = function(self, key)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
    txn = function(self, payload)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
    get = function(self, path)
        return nil, "Consul support has been removed. Use Store abstraction instead."
    end,
}

-- Provide stub instance
_M.instance = stub_instance

-- Initialization does nothing
function _M.init()
    return true
end

return _M
