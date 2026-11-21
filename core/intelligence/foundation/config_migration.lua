IntelligenceConfigMigration = {}
local Migration = IntelligenceConfigMigration

local transient = {
  combatActive = true,
  emergency = true,
  currentTarget = true,
  currentPath = true,
  runtime = true,
  learned = true,
  replay = true,
  diagnostics = true,
}

local function clean(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do
    if not transient[key] then result[key] = clean(child) end
  end
  return result
end

function Migration.migrate(sources)
  sources = sources or {}
  if sources.intelligence and sources.intelligence.version == 5 then return clean(sources.intelligence) end
  return {
    version = 5,
    settings = clean(sources.unified or {}),
    profiles = {
      targetbot = clean(sources.targetbotProfile or {}),
      cavebot = clean(sources.cavebotProfile or {}),
    },
    models = { defaultMode = "SHADOW" },
    flags = { replay = true, diagnostics = true, learning = true, neuralModel = false, routeAlternatives = true },
  }
end

function Migration.readProfiles(resources, codec, root, selected)
  local profiles = {}
  if not resources or not resources.fileExists or not resources.readFileContents then return profiles end
  for name, spec in pairs({
    targetbot = { dir = "targetbot_configs/", ext = ".json" },
    cavebot = { dir = "cavebot_configs/", ext = ".cfg" },
  }) do
    local profileName = selected and selected[name]
    local path = profileName and root .. spec.dir .. profileName .. spec.ext
    if path and resources.fileExists(path) then
      local ok, content = pcall(resources.readFileContents, path)
      if ok and type(content) == "string" then
        local value = content
        if name == "targetbot" and codec and codec.decode then
          local decoded, data = pcall(codec.decode, content)
          if decoded and type(data) == "table" then value = data end
        end
        profiles[name] = { name = profileName, content = value }
      end
    end
  end
  return profiles
end

return Migration
