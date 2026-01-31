--[[
  SafeCreature - Consolidated safe creature accessor functions
  
  Replaces 60+ duplicate pcall patterns like:
    local ok, result = pcall(function() return creature:getPosition() end)
  
  With single-call safe accessors:
    local pos = SafeCreature.getPosition(creature)
  
  BENEFITS:
  - Reduces code duplication
  - Consistent error handling
  - Slightly better performance (reuses pcall wrapper)
  - Easier to add logging/telemetry
]]

local SafeCreature = {}

-- ============================================================================
-- BASIC ACCESSORS
-- ============================================================================

--[[
  Get creature ID safely
  @param creature Creature object
  @return number|nil ID or nil if invalid
]]
function SafeCreature.getId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

--[[
  Get creature name safely
  @param creature Creature object
  @return string|nil Name or nil if invalid
]]
function SafeCreature.getName(creature)
  if not creature then return nil end
  local ok, name = pcall(function() return creature:getName() end)
  return ok and name or nil
end

--[[
  Get creature position safely
  @param creature Creature object
  @return Position|nil Position table or nil if invalid
]]
function SafeCreature.getPosition(creature)
  if not creature then return nil end
  local ok, pos = pcall(function() return creature:getPosition() end)
  return ok and pos or nil
end

--[[
  Get creature health percent safely
  @param creature Creature object
  @return number Health percent (0-100) or 100 if invalid
]]
function SafeCreature.getHealthPercent(creature)
  if not creature then return 100 end
  local ok, hp = pcall(function() return creature:getHealthPercent() end)
  return ok and hp or 100
end

--[[
  Get creature direction safely
  @param creature Creature object
  @return number|nil Direction (0-7) or nil if invalid
]]
function SafeCreature.getDirection(creature)
  if not creature then return nil end
  local ok, dir = pcall(function() return creature:getDirection() end)
  return ok and dir or nil
end

--[[
  Get creature speed safely
  @param creature Creature object
  @return number Speed or 0 if invalid
]]
function SafeCreature.getSpeed(creature)
  if not creature then return 0 end
  local ok, speed = pcall(function() return creature:getSpeed() end)
  return ok and speed or 0
end

-- ============================================================================
-- TYPE CHECKS
-- ============================================================================

--[[
  Check if creature is a monster safely
  @param creature Creature object
  @return boolean
]]
function SafeCreature.isMonster(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isMonster() end)
  return ok and result == true
end

--[[
  Check if creature is a player safely
  @param creature Creature object
  @return boolean
]]
function SafeCreature.isPlayer(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isPlayer() end)
  return ok and result == true
end

--[[
  Check if creature is an NPC safely
  @param creature Creature object
  @return boolean
]]
function SafeCreature.isNpc(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isNpc() end)
  return ok and result == true
end

--[[
  Check if creature is dead safely
  @param creature Creature object
  @return boolean
]]
function SafeCreature.isDead(creature)
  if not creature then return true end
  local ok, result = pcall(function() return creature:isDead() end)
  return ok and result == true
end

--[[
  Check if creature is walking safely
  @param creature Creature object
  @return boolean
]]
function SafeCreature.isWalking(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isWalking() end)
  return ok and result == true
end

-- ============================================================================
-- COMBAT ACCESSORS
-- ============================================================================

--[[
  Get creature skull safely
  @param creature Creature object
  @return number Skull type or 0 if invalid
]]
function SafeCreature.getSkull(creature)
  if not creature then return 0 end
  local ok, skull = pcall(function() return creature:getSkull() end)
  return ok and skull or 0
end

--[[
  Get creature outfit safely
  @param creature Creature object
  @return table|nil Outfit table or nil if invalid
]]
function SafeCreature.getOutfit(creature)
  if not creature then return nil end
  local ok, outfit = pcall(function() return creature:getOutfit() end)
  return ok and outfit or nil
end

-- ============================================================================
-- BULK ACCESSOR (Single pcall for multiple properties)
-- ============================================================================

--[[
  Get multiple creature properties in a single pcall
  More efficient when you need several values at once
  @param creature Creature object
  @return table with properties or nil if creature invalid
]]
function SafeCreature.getAll(creature)
  if not creature then return nil end
  
  local ok, result = pcall(function()
    return {
      id = creature:getId(),
      name = creature:getName(),
      position = creature:getPosition(),
      healthPercent = creature:getHealthPercent(),
      direction = creature:getDirection(),
      isMonster = creature:isMonster(),
      isPlayer = creature:isPlayer(),
      isDead = creature:isDead(),
    }
  end)
  
  return ok and result or nil
end

--[[
  Validate creature is usable (not nil, not dead, has valid ID)
  @param creature Creature object
  @return boolean, table|nil (isValid, properties if valid)
]]
function SafeCreature.validate(creature)
  if not creature then return false, nil end
  
  local ok, props = pcall(function()
    local id = creature:getId()
    local dead = creature:isDead()
    if not id or dead then return nil end
    return {
      id = id,
      name = creature:getName(),
      position = creature:getPosition(),
      healthPercent = creature:getHealthPercent(),
      isMonster = creature:isMonster(),
    }
  end)
  
  if not ok or not props then return false, nil end
  return true, props
end

-- ============================================================================
-- DISTANCE HELPERS
-- ============================================================================

--[[
  Calculate distance between two positions
  @param pos1 Position table
  @param pos2 Position table
  @return number Distance or 999 if invalid
]]
function SafeCreature.distance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  if pos1.z ~= pos2.z then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

--[[
  Get distance from creature to a position
  @param creature Creature object
  @param targetPos Position table
  @return number Distance or 999 if invalid
]]
function SafeCreature.distanceTo(creature, targetPos)
  local creaturePos = SafeCreature.getPosition(creature)
  return SafeCreature.distance(creaturePos, targetPos)
end

--[[
  Get distance between two creatures
  @param creature1 Creature object
  @param creature2 Creature object  
  @return number Distance or 999 if invalid
]]
function SafeCreature.distanceBetween(creature1, creature2)
  local pos1 = SafeCreature.getPosition(creature1)
  local pos2 = SafeCreature.getPosition(creature2)
  return SafeCreature.distance(pos1, pos2)
end

-- ============================================================================
-- GLOBAL EXPORT
-- ============================================================================

-- Expose as global for use by all modules (no _G in OTClient sandbox)
-- SafeCreature is already global (declared without 'local')

return SafeCreature
