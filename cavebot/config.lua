CaveBot.Config = { values = {}, default_values = {} }

function CaveBot.Config.setup()
  local extras = storage.extras or {}
  CaveBot.Config.add("ping", 100)
  CaveBot.Config.add("walkDelay", 10)
  CaveBot.Config.add("ignoreFields", true)
  CaveBot.Config.add("mapClick", true)
  CaveBot.Config.add("useDelay", 400)
  CaveBot.Config.add("autoUseTools", true)
  CaveBot.Config.add("autoOpenDoors", true)
  CaveBot.Config.add("ropeToolId", tonumber(extras.rope) or 3003)
  CaveBot.Config.add("shovelToolId", tonumber(extras.shovel) or 3457)
  CaveBot.Config.add("macheteToolId", tonumber(extras.machete) or 3308)
  CaveBot.Config.add("scytheToolId", tonumber(extras.scythe) or 3453)
end

function CaveBot.Config.onConfigChange(_, _, configData)
  for key, defaultValue in pairs(CaveBot.Config.default_values) do
    CaveBot.Config.values[key] = defaultValue
  end
  for key, value in pairs(configData or {}) do
    if CaveBot.Config.default_values[key] ~= nil then CaveBot.Config.values[key] = value end
  end
end

function CaveBot.Config.save() return CaveBot.Config.values end

function CaveBot.Config.add(id, defaultValue)
  if CaveBot.Config.default_values[id] ~= nil then return warn("Duplicated config key: " .. id) end
  CaveBot.Config.default_values[id] = defaultValue
  CaveBot.Config.values[id] = defaultValue
end

function CaveBot.Config.get(id) return CaveBot.Config.values[id] end

function CaveBot.Config.set(id, value)
  if CaveBot.Config.default_values[id] == nil then return false end
  CaveBot.Config.values[id] = value
  return true
end

function CaveBot.Config.show()
  if nExBot.UI and nExBot.UI.Shell then nExBot.UI.Shell.select("cavebot") end
end

function CaveBot.Config.hide() end
