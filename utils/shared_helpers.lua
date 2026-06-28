local SharedHelpers = {}

function SharedHelpers.getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

function SharedHelpers.setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

local _pathUtilsLoaded = false
function SharedHelpers.ensurePathUtils()
  if _pathUtilsLoaded then return true end
  local ok = pcall(function() dofile("nExBot/utils/path_utils.lua") end)
  if ok then
    _pathUtilsLoaded = true
    return true
  end
  return false
end

function SharedHelpers.makeDebounce(ms, fn)
  if nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
    return nExBot.EventUtil.debounce(ms, fn)
  end
  local scheduled = false
  return function(...)
    if scheduled then return end
    scheduled = true
    local args = {...}
    schedule(ms, function()
      scheduled = false
      if #args > 0 then
        pcall(fn, table.unpack(args))
      else
        pcall(fn)
      end
    end)
  end
end

nExBot.SharedHelpers = SharedHelpers
return SharedHelpers
