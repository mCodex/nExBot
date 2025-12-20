-- Lightweight Event debounce/coalesce utility
-- Usage: local d = EventDebouncer.debounce(100, handler)
-- then call d(args...) repeatedly; handler will run at most once per delay window

nExBot = nExBot or {}
nExBot.EventUtil = nExBot.EventUtil or {}

local EventDebouncer = {}

-- Returns a function that coalesces repeated calls and invokes `fn` once after `delay` ms
function EventDebouncer.debounce(delay, fn)
  local token = 0
  local lastArgs = nil
  return function(...)
    local myToken = token + 1
    token = myToken
    lastArgs = {...}
    schedule(delay, function()
      -- only run if token hasn't advanced beyond our scheduled token
      if token == myToken then
        fn(table.unpack(lastArgs or {}))
        lastArgs = nil
      end
    end)
  end
end

nExBot.EventUtil.debounce = EventDebouncer.debounce

return EventDebouncer