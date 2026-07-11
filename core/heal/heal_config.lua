local M = {}

local DEFAULT_PROFILE = {
  enabled = false,
  spellTable = {},
  itemTable = {},
  name = nil,  -- set per profile
  Visible = true,
  Cooldown = true,
  Interval = true,
  Conditions = true,
  Delay = true,
  MessageDelay = false,
}

function M.createDefaults()
  local profiles = {}
  for i = 1, 5 do
    profiles[i] = {}
    for k, v in pairs(DEFAULT_PROFILE) do
      profiles[i][k] = v
    end
    profiles[i].name = "Profile #" .. i
  end
  return profiles
end

function M.validateProfile(profile)
  if type(profile) ~= "table" then return false end
  if profile.spellTable == nil then return false end
  if profile.itemTable == nil then return false end
  return true
end

function M.ensureDefaults(config, panelName)
  if type(config) ~= "table" then return end
  if type(config[panelName]) ~= "table" then
    config[panelName] = M.createDefaults()
    return
  end
  for i = 1, 5 do
    if not M.validateProfile(config[panelName][i]) then
      local defaults = M.createDefaults()
      config[panelName][i] = defaults[i]
    end
  end
end

return M
