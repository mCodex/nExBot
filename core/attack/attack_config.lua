local M = {}

local DEFAULT_PROFILE = {
  enabled = false,
  attackTable = {},
  ignoreMana = true,
  Kills = false,
  Rotate = false,
  name = nil,
  Cooldown = true,
  Visible = true,
  pvpMode = false,
  KillsAmount = 1,
  PvpSafe = true,
  BlackListSafe = false,
  AntiRsRange = 5,
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
  profiles[1].enabled = true
  return profiles
end

function M.validateProfile(profile)
  if type(profile) ~= "table" then return false end
  if profile.attackTable == nil then return false end
  return true
end

function M.ensureDefaults(config, panelName)
  if type(config) ~= "table" then return end
  if type(config[panelName]) ~= "table" then
    config[panelName] = M.createDefaults()
    return
  end
  local defaults = M.createDefaults()
  for i = 1, 5 do
    if type(config[panelName][i]) ~= "table" then
      config[panelName][i] = defaults[i]
    end
  end
end

function M.getActiveProfile(config, panelName)
  local n = config.currentBotProfile
  if type(n) ~= "number" or n < 1 or n > 5 then
    n = 1
  end
  return config[panelName][n]
end

return M
