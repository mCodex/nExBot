local panelName = "supplies"
if not SuppliesConfig[panelName] or SuppliesConfig[panelName].item1 then
  SuppliesConfig[panelName] = {
    currentProfile = "Default",
    ["Default"] = {}
  }
end

local function convertOldConfig(config)
  if config and config.items then
    return config
  end -- config is new

  local newConfig = {
    items = {},
    capSwitch = config.capSwitch,
    SoftBoots = config.SoftBoots,
    imbues = config.imbues,
    staminaSwitch = config.staminaSwitch,
    capValue = config.capValue,
    staminaValue = config.staminaValue
  }

  local items = {
    config.item1,
    config.item2,
    config.item3,
    config.item4,
    config.item5,
    config.item6
  }
  local mins = {
    config.item1Min,
    config.item2Min,
    config.item3Min,
    config.item4Min,
    config.item5Min,
    config.item6Min
  }
  local maxes = {
    config.item1Max,
    config.item2Max,
    config.item3Max,
    config.item4Max,
    config.item5Max,
    config.item6Max
  }

  for i, item in ipairs(items) do
    if item > 100 then
      local min = mins[i]
      local max = maxes[i]
      newConfig.items[tostring(item)] = {
        min = min,
        max = max,
        avg = 0
      }
    end
  end

  return newConfig
end

-- convert old configs
for k, profile in pairs(SuppliesConfig[panelName]) do
  if type(profile) == 'table' then
    SuppliesConfig[panelName][k] = convertOldConfig(profile)
  end
end

local currentProfile = SuppliesConfig[panelName].currentProfile
local config = SuppliesConfig[panelName][currentProfile]

nExBotConfigSave("supply")

if not config then
  for k, v in pairs(SuppliesConfig[panelName]) do
    if type(v) == "table" then
      SuppliesConfig[panelName].currentProfile = k
      config = SuppliesConfig[panelName][k]
      break
    end
  end
end
Supplies = {} -- public functions

local function save()
  nExBotConfigSave("supply")
end

Supplies.show = function()
  -- Retired standalone window; kept as a safe no-op for the Actions bridge.
end

Supplies.getItemsData = function()
  local t = {}
  for id, data in pairs(config.items or {}) do
    t[id] = { min = data.min, max = data.max, avg = data.avg }
  end
  return t
end

Supplies.isSupplyItem = function(id)
  local data = Supplies.getItemsData()
  id = tostring(id)

  if data[id] then
    return data[id]
  else
    return false
  end
end

Supplies.hasEnough = function()
  local data = Supplies.getItemsData()

  for key, values in pairs(data) do
    local id = tonumber(key)
    local minimum = values.min
    local current = player:getItemsCount(id) or 0

    if current < minimum then
      return {id=id, amount=current}
    end
  end

  return true
end

hasSupplies = Supplies.hasEnough

Supplies.getAdditionalData = function()
  local data = {
    stamina = {enabled = config.staminaSwitch, value = config.staminaValue},
    capacity = {enabled = config.capSwitch, value = config.capValue},
    softBoots = {enabled = config.SoftBoots},
    imbues = {enabled = config.imbues}
  }
  return data
end

Supplies.getFullData = function()
  local data = {
    items = Supplies.getItemsData(),
    additional = Supplies.getAdditionalData()
  }

  return data
end

Supplies.getCurrentProfile = function()
  return SuppliesConfig[panelName].currentProfile
end

Supplies.listProfiles = function()
  local profiles = {}
  for name, profile in pairs(SuppliesConfig[panelName]) do
    if type(profile) == "table" then profiles[#profiles + 1] = name end
  end
  table.sort(profiles)
  return profiles
end

Supplies.setCurrentProfile = function(name)
  if type(name) ~= "string" or type(SuppliesConfig[panelName][name]) ~= "table" then return false end
  SuppliesConfig[panelName].currentProfile = name
  currentProfile = name
  config = SuppliesConfig[panelName][name]
  save()
  return true
end

Supplies.createProfile = function()
  local n = #Supplies.listProfiles()
  if n > 6 then
    warn("You cannot create more than 6 profiles.")
    return false, "You cannot create more than 6 profiles."
  end
  local name = "Profile #" .. n + 1
  SuppliesConfig[panelName][name] = {items = {}}
  save()
  return true, name
end

Supplies.setItem = function(id, min, max, avg)
  id = tonumber(id)
  min, max, avg = tonumber(min), tonumber(max), tonumber(avg)
  if not id or id <= 100 or not min or not max or not avg then return false end
  if id % 1 ~= 0 or min % 1 ~= 0 or max % 1 ~= 0 or avg % 1 ~= 0 then return false end
  if min < 0 or max < 0 or avg < 0 then return false end

  config.items[tostring(id)] = { min = min, max = max, avg = avg }
  save()
  return true
end

Supplies.removeItem = function(id)
  id = tonumber(id)
  if not id or not config.items[tostring(id)] then return false end
  config.items[tostring(id)] = nil
  save()
  return true
end

Supplies.setCondition = function(name, enabled, value)
  local fields = {
    capacity = { enabled = "capSwitch", value = "capValue" },
    stamina = { enabled = "staminaSwitch", value = "staminaValue" },
    softBoots = { enabled = "SoftBoots" },
    imbues = { enabled = "imbues" },
  }
  local field = fields[name]
  if not field then return false end

  if field.value and value ~= nil then
    value = tonumber(value)
    if not value or value < 0 or value % 1 ~= 0 then return false end
  end

  config[field.enabled] = enabled == true
  if field.value and value ~= nil then config[field.value] = value end
  save()
  return true
end
