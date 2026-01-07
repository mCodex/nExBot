-- Lightweight Event debounce/coalesce utility
-- Usage: local d = EventDebouncer.debounce(100, handler)
-- then call d(args...) repeatedly; handler will run at most once per delay window

nExBot = nExBot or {}
nExBot.EventUtil = nExBot.EventUtil or {}

local EventDebouncer = {}

-- Returns a function that coalesces repeated calls and invokes `fn` once after `delay` ms
local function safe_unpack(tbl)
  if not tbl then return end
  if table and table.unpack then return table.unpack(tbl) end
  if unpack then return unpack(tbl) end
  local n = #tbl
  if n == 0 then return end
  if n == 1 then return tbl[1] end
  if n == 2 then return tbl[1], tbl[2] end
  if n == 3 then return tbl[1], tbl[2], tbl[3] end
  if n == 4 then return tbl[1], tbl[2], tbl[3], tbl[4] end
  if n == 5 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5] end
  if n == 6 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6] end
  if n == 7 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7] end
  if n == 8 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8] end
  if n == 9 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9] end
  if n == 10 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10] end
  if n == 11 then return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11] end
  return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11], tbl[12]
end

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
        fn(safe_unpack(lastArgs or {}))
        lastArgs = nil
      end
    end)
  end
end

nExBot.EventUtil.debounce = EventDebouncer.debounce

return EventDebouncer