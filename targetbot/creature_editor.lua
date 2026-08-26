-- Creature-rule persistence for TargetBot. The interactive form now lives
-- inline in the shell Target page (ui/modules/workflows/target.lua); this
-- file owns the domain logic: name-pattern parsing and add/update.

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Parse name patterns into include and exclude regex lists.
-- "name1, name2, !exclude1" -> includes, excludes (mirrors creature.lua)
local function parsePatterns(name)
  local includes = {}
  local excludes = {}
  for part in string.gmatch(name, "[^,]+") do
    local trimmed = trim(part):lower()
    if trimmed:sub(1, 1) == "!" then
      local excludeName = trim(trimmed:sub(2))
      if excludeName:len() > 0 then
        table.insert(excludes, "^" .. excludeName:gsub("%*", ".*"):gsub("%?", ".?") .. "$")
      end
    else
      table.insert(includes, "^" .. trimmed:gsub("%*", ".*"):gsub("%?", ".?") .. "$")
    end
  end
  return includes, excludes
end

-- Persist a creature rule. data = { entry = <widget>?, name = ..., ... }.
-- With an entry it updates that rule (preserving untouched fields); without
-- one it adds a new rule. Returns true on success.
TargetBot.saveCreature = function(data)
  data = data or {}
  local entry = data.entry
  local config = {}
  if entry and entry.value then
    for key, value in pairs(entry.value) do config[key] = value end
  end
  for key, value in pairs(data) do
    if key ~= "entry" then config[key] = value end
  end
  if not config.name or trim(config.name) == "" then return false end

  local includes, excludes = parsePatterns(config.name)
  config.regex = #includes > 0 and table.concat(includes, "|") or "^$"
  config.excludeRegex = #excludes > 0 and table.concat(excludes, "|") or nil

  if entry then
    entry:setText(config.name)
    entry.value = config
    TargetBot.Creature.resetConfigsCache()
  else
    TargetBot.Creature.addConfig(config, true)
  end
  TargetBot.save()
  return true
end

-- Legacy standalone editor entry point; the shell page edits inline now.
TargetBot.showCreatureEditor = function() end