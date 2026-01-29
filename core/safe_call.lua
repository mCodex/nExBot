-- Safe Global Function Calls Utility
-- Provides safe wrappers for global functions to prevent "attempt to call global 'function_name' (a nil value)" errors
-- Follows DRY, KISS, SRP principles with pure functions

SafeCall = SafeCall or {}

-- Helper function to safely call a function by name
-- Uses pcall to prevent errors when functions don't exist
local function safeCallFunction(func, ...)
    if func then
        local success, result = pcall(func, ...)
        if success then
            return result
        end
    end
    return nil
end

-- Pure function: Safely call a global function with arguments
-- @param funcName: string name of the global function
-- @param ...: arguments to pass to the function
-- @return: result of the function call or nil if function doesn't exist
function SafeCall.global(funcName, ...)
    -- This is a fallback for dynamic function calls
    -- For performance, use the cached convenience functions below
    return safeCallFunction(_G and _G[funcName], ...)
end

-- Pure function: Safely call a global function that returns a value, with fallback
-- @param funcName: string name of the global function
-- @param fallback: value to return if function doesn't exist or returns nil
-- @param ...: arguments to pass to the function
-- @return: result of the function call or fallback value
function SafeCall.globalWithFallback(funcName, fallback, ...)
    local result = SafeCall.global(funcName, ...)
    return result ~= nil and result or fallback
end

-- Pure function: Safely call a function that returns a boolean
-- @param funcName: string name of the global function
-- @param ...: arguments to pass to the function
-- @return: boolean result or false if function doesn't exist
function SafeCall.bool(funcName, ...)
    local result = SafeCall.global(funcName, ...)
    return result and true or false
end

-- Pure function: Safely call a function that returns a number
-- @param funcName: string name of the global function
-- @param ...: arguments to pass to the function
-- @return: number result or 0 if function doesn't exist
function SafeCall.number(funcName, ...)
    local result = SafeCall.global(funcName, ...)
    return type(result) == "number" and result or 0
end

-- Pure function: Safely call a function that returns a table
-- @param funcName: string name of the global function
-- @param ...: arguments to pass to the function
-- @return: table result or empty table if function doesn't exist
function SafeCall.table(funcName, ...)
    local result = SafeCall.global(funcName, ...)
    return type(result) == "table" and result or {}
end

-- Pure function: Safely call a function that returns a string
-- @param funcName: string name of the global function
-- @param ...: arguments to pass to the function
-- @return: string result or empty string if function doesn't exist
function SafeCall.string(funcName, ...)
    local result = SafeCall.global(funcName, ...)
    return type(result) == "string" and result or ""
end

-- High-performance cached versions for frequently used functions
SafeCall._cache = SafeCall._cache or {}

-- Pure function: Get cached safe caller for a function name
-- @param funcName: string name of the global function
-- @return: function that safely calls the global function
function SafeCall.getCachedCaller(funcName)
    if not SafeCall._cache[funcName] then
        SafeCall._cache[funcName] = function(...)
            return SafeCall.global(funcName, ...)
        end
    end
    return SafeCall._cache[funcName]
end

-- Convenience functions for commonly used global functions
-- These use direct safe calls following the existing codebase patterns
function SafeCall.getMonsters(...) return safeCallFunction(getMonsters, ...) end
function SafeCall.target(...) return safeCallFunction(target, ...) end
function SafeCall.getContainerByItem(...) return safeCallFunction(getContainerByItem, ...) end
function SafeCall.isAttSpell(...) return safeCallFunction(isAttSpell, ...) end
function SafeCall.getFirstNumberInText(...) return safeCallFunction(getFirstNumberInText, ...) end
function SafeCall.getCreatureByName(...) return safeCallFunction(getCreatureByName, ...) end
function SafeCall.useWith(...) return safeCallFunction(useWith, ...) end
function SafeCall.findItem(...) return safeCallFunction(findItem, ...) end
function SafeCall.getTarget(...) return safeCallFunction(getTarget, ...) end
function SafeCall.isInPz(...) return safeCallFunction(isInPz, ...) end
function SafeCall.isParalyzed(...) return safeCallFunction(isParalyzed, ...) end
function SafeCall.getPlayers(...) return safeCallFunction(getPlayers, ...) end
function SafeCall.regexMatch(...) return safeCallFunction(regexMatch, ...) end
function SafeCall.exp(...) return safeCallFunction(exp, ...) end
function SafeCall.getPrice(...) return safeCallFunction(getPrice, ...) end
function SafeCall.getColor(...) return safeCallFunction(getColor, ...) end

-- Recursive function: Safely traverse nested function calls
-- @param funcChain: table of {funcName, args...} pairs
-- @return: final result or nil
function SafeCall.chain(funcChain)
    if not funcChain or #funcChain == 0 then return nil end

    local result = nil
    for i, callSpec in ipairs(funcChain) do
        local funcName = callSpec[1]
        local args = {}
        for j = 2, #callSpec do
            args[j-1] = callSpec[j]
        end

        -- For chained calls, we need to get the function dynamically
        -- This is less common, so we use the global method
        local func = SafeCall.global(funcName)
        if not func then return nil end

        if i == 1 then
            result = func(unpack(args))
        else
            if type(result) ~= "table" or not result[funcName] then return nil end
            result = result[funcName](unpack(args))
        end
    end

    return result
end

-- Pure function: Create a safe version of any function
-- @param originalFunc: the original function (can be nil)
-- @param fallback: fallback value to return if function is nil
-- @return: safe wrapper function
function SafeCall.wrap(originalFunc, fallback)
    return function(...)
        if originalFunc then
            local result = originalFunc(...)
            return result ~= nil and result or fallback
        end
        return fallback
    end
end

-- Safely call any function with pcall and return success flag and result
function SafeCall.call(func, ...)
    if func then
        local ok, res = pcall(func, ...)
        if ok then return true, res end
    end
    return false, nil
end

-- Export to global namespace for easy access (OTClient doesn't have _G)
SafeCall = SafeCall  -- Makes it globally accessible

return SafeCall