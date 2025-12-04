--[[
  nExBot Spell Registry
  Open/Closed Principle implementation for spell management
  Extensible without modification
  
  Author: nExBot Team
  Version: 1.0.0
]]

local SpellRegistry = {
  spells = {},
  handlers = {},
  categories = {}
}

-- Create new registry instance
function SpellRegistry:new()
  local instance = {
    spells = {},
    handlers = {},
    categories = {
      attack = {},
      healing = {},
      support = {},
      summon = {}
    }
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

-- Register a spell with its handler
-- @param spellName string - Spell name/words
-- @param config table - Spell configuration
-- @param handler function - Optional custom handler
function SpellRegistry:register(spellName, config, handler)
  spellName = spellName:lower()
  
  self.spells[spellName] = {
    name = spellName,
    displayName = config.displayName or spellName,
    manaCost = config.manaCost or 0,
    cooldown = config.cooldown or 2000,
    level = config.level or 1,
    vocations = config.vocations or {},
    type = config.type or "attack",
    range = config.range or 1,
    pattern = config.pattern,
    element = config.element,
    avgDamage = config.avgDamage or 0,
    priority = config.priority or 0
  }
  
  if handler then
    self.handlers[spellName] = handler
  end
  
  -- Add to category
  local category = config.type or "attack"
  if self.categories[category] then
    table.insert(self.categories[category], spellName)
  end
  
  return self
end

-- Unregister a spell
function SpellRegistry:unregister(spellName)
  spellName = spellName:lower()
  
  local spell = self.spells[spellName]
  if spell then
    -- Remove from category
    local category = spell.type
    if self.categories[category] then
      for i, name in ipairs(self.categories[category]) do
        if name == spellName then
          table.remove(self.categories[category], i)
          break
        end
      end
    end
  end
  
  self.spells[spellName] = nil
  self.handlers[spellName] = nil
end

-- Get spell configuration
function SpellRegistry:get(spellName)
  return self.spells[spellName:lower()]
end

-- Check if spell exists
function SpellRegistry:exists(spellName)
  return self.spells[spellName:lower()] ~= nil
end

-- Cast a spell using its handler
function SpellRegistry:cast(spellName)
  spellName = spellName:lower()
  
  local spell = self.spells[spellName]
  if not spell then
    return false, "Spell not found"
  end
  
  local handler = self.handlers[spellName]
  if handler then
    return handler(spell)
  else
    -- Default handler: just say the spell
    if say then
      say(spellName)
      return true
    end
  end
  
  return false, "No handler available"
end

-- Get all spells by category
function SpellRegistry:getByCategory(category)
  local result = {}
  
  if self.categories[category] then
    for _, spellName in ipairs(self.categories[category]) do
      table.insert(result, self.spells[spellName])
    end
  end
  
  return result
end

-- Get all spells for a vocation
function SpellRegistry:getByVocation(vocationId)
  local result = {}
  
  for name, spell in pairs(self.spells) do
    if #spell.vocations == 0 then
      -- No vocation restriction
      table.insert(result, spell)
    else
      for _, voc in ipairs(spell.vocations) do
        if voc == vocationId then
          table.insert(result, spell)
          break
        end
      end
    end
  end
  
  -- Sort by priority
  table.sort(result, function(a, b)
    return a.priority > b.priority
  end)
  
  return result
end

-- Get all registered spell names
function SpellRegistry:getAll()
  local names = {}
  for name, _ in pairs(self.spells) do
    table.insert(names, name)
  end
  return names
end

-- Get count of registered spells
function SpellRegistry:count()
  local count = 0
  for _ in pairs(self.spells) do
    count = count + 1
  end
  return count
end

-- Register multiple spells at once
function SpellRegistry:registerBulk(spellList)
  for _, spell in ipairs(spellList) do
    self:register(spell.name, spell.config, spell.handler)
  end
  return self
end

-- Export all spell data (for debugging/saving)
function SpellRegistry:export()
  local data = {}
  for name, spell in pairs(self.spells) do
    data[name] = {
      displayName = spell.displayName,
      manaCost = spell.manaCost,
      cooldown = spell.cooldown,
      level = spell.level,
      vocations = spell.vocations,
      type = spell.type,
      range = spell.range,
      element = spell.element,
      avgDamage = spell.avgDamage
    }
  end
  return data
end

-- Import spell data
function SpellRegistry:import(data)
  for name, config in pairs(data) do
    self:register(name, config)
  end
  return self
end

return SpellRegistry
