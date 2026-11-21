local SilentRestore = {}
SilentRestore.__index = SilentRestore

local _active = false
local _callbacks = {}

function SilentRestore.isActive()
  return _active
end

function SilentRestore.apply(fn)
  if _active then
    -- Nested silent restore - just run
    return fn()
  end
  
  _active = true
  local ok, result = pcall(fn)
  _active = false
  
  if not ok then
    error(result)
  end
  
  return result
end

function SilentRestore.wrapCallback(originalCallback)
  return function(...)
    if SilentRestore.isActive() then
      -- During silent restore, don't persist or emit events
      return
    end
    return originalCallback(...)
  end
end

function SilentRestore.registerCallback(event, callback)
  _callbacks[event] = _callbacks[event] or {}
  table.insert(_callbacks[event], callback)
end

function SilentRestore.emit(event, data)
  if _active then return end
  for _, cb in ipairs(_callbacks[event] or {}) do
    pcall(cb, data)
  end
end

nExBot = nExBot or {}
nExBot.SilentRestore = SilentRestore

return SilentRestore