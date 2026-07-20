local OTClientAdapter = {}
OTClientAdapter.__index = OTClientAdapter

function OTClientAdapter.new()
  local self = setmetatable({}, OTClientAdapter)
  self.capabilities = {}
  self:resolveCapabilities()
  return self
end

function OTClientAdapter:resolveCapabilities()
  local C = g_game
  local g = g_game
  
  self.capabilities = {
    -- Player state
    getLocalPlayer = function()
      local lp = g.getLocalPlayer and g.getLocalPlayer()
      if not lp and C and C.getLocalPlayer then lp = C.getLocalPlayer() end
      return lp
    end,
    
    getHealth = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getHealth and lp:getHealth() or 0
    end,
    
    getMaxHealth = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getMaxHealth and lp:getMaxHealth() or 1
    end,
    
    getMana = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getMana and lp:getMana() or 0
    end,
    
    getMaxMana = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getMaxMana and lp:getMaxMana() or 1
    end,
    
    getPosition = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getPosition and lp:getPosition() or {x=0,y=0,z=0}
    end,
    
    getStates = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getStates and lp:getStates() or {}
    end,
    
    getLevel = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getLevel and lp:getLevel() or 1
    end,
    
    getExperience = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getExperience and lp:getExperience() or 0
    end,
    
    getCapacity = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getCapacity and lp:getCapacity() or 0
    end,
    
    getFreeCapacity = function()
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getFreeCapacity and lp:getFreeCapacity() or 0
    end,
    
    -- Attack target
    getAttackingCreature = function()
      return g.getAttackingCreature and g.getAttackingCreature()
    end,
    
    -- Creatures
    getSpectators = function(pos, multifloor, includePlayers)
      return g.getSpectators and g.getSpectators(pos, multifloor, includePlayers) or {}
    end,
    
    -- Containers/Inventory
    getContainer = function(index)
      return g.getContainer and g.getContainer(index)
    end,
    
    getContainers = function()
      return g.getContainers and g.getContainers() or {}
    end,
    
    getInventoryItem = function(slot)
      local lp = self.capabilities.getLocalPlayer()
      return lp and lp.getInventoryItem and lp:getInventoryItem(slot)
    end,
    
    -- Network stats (misspelled in OTClient)
    getRecvPacketsCount = function()
      return g.getRecivedPacketsCount and g.getRecivedPacketsCount() 
          or g.getRecvPacketsCount and g.getRecvPacketsCount() 
          or 0
    end,
    
    getRecvPacketsSize = function()
      return g.getRecivedPacketsSize and g.getRecivedPacketsSize()
          or g.getRecvPacketsSize and g.getRecvPacketsSize()
          or 0
    end,
    
    getSentPacketsCount = function()
      return g.getSentPacketsCount and g.getSentPacketsCount() or 0
    end,
    
    getSentPacketsSize = function()
      return g.getSentPacketsSize and g.getSentPacketsSize() or 0
    end,
    
    getPing = function()
      return g.getPing and g.getPing() or 0
    end,
    
    -- Spells
    isSpellReady = function(spellName)
      return g.isSpellReady and g.isSpellReady(spellName) or false
    end,
    
    getSpellCooldown = function(spellName)
      return g.getSpellCooldown and g.getSpellCooldown(spellName) or 0
    end,
    
    -- Pathfinding
    findPath = function(startPos, endPos, options)
      if not g.findPath then return nil end
      options = options or {}
      return g.findPath(startPos, endPos, {
        maxSteps = options.maxSteps or 100,
        ignoreNonPathable = options.ignoreNonPathable or false,
        ignoreCreatures = options.ignoreCreatures or false,
        ignoreCost = options.ignoreCost or false,
        precision = options.precision or 1,
        allowOnlyVisibleTiles = options.allowOnlyVisibleTiles or false,
      })
    end,
    
    -- Floor change detection
    isOnline = function()
      return g.isOnline and g.isOnline() or false
    end,
    
    -- Misspelling isolation
    _misspelling = {
      recv = "getRecivedPacketsCount",
      recvSize = "getRecivedPacketsSize",
    },
  }
end

function OTClientAdapter:getHealth()
  return self.capabilities.getHealth()
end

function OTClientAdapter:getMaxHealth()
  return self.capabilities.getMaxHealth()
end

function OTClientAdapter:getMana()
  return self.capabilities.getMana()
end

function OTClientAdapter:getMaxMana()
  return self.capabilities.getMaxMana()
end

function OTClientAdapter:getPosition()
  return self.capabilities.getPosition()
end

function OTClientAdapter:getStates()
  return self.capabilities.getStates()
end

function OTClientAdapter:getAttackingCreature()
  return self.capabilities.getAttackingCreature()
end

function OTClientAdapter:getSpectators(pos, multifloor, includePlayers)
  return self.capabilities.getSpectators(pos, multifloor, includePlayers)
end

function OTClientAdapter:getContainers()
  return self.capabilities.getContainers()
end

function OTClientAdapter:getInventoryItem(slot)
  return self.capabilities.getInventoryItem(slot)
end

function OTClientAdapter:getRecvPacketsCount()
  return self.capabilities.getRecvPacketsCount()
end

function OTClientAdapter:getRecvPacketsSize()
  return self.capabilities.getRecvPacketsSize()
end

function OTClientAdapter:getSentPacketsCount()
  return self.capabilities.getSentPacketsCount()
end

function OTClientAdapter:getSentPacketsSize()
  return self.capabilities.getSentPacketsSize()
end

function OTClientAdapter:getPing()
  return self.capabilities.getPing()
end

function OTClientAdapter:isSpellReady(spellName)
  return self.capabilities.isSpellReady(spellName)
end

function OTClientAdapter:getSpellCooldown(spellName)
  return self.capabilities.getSpellCooldown(spellName)
end

function OTClientAdapter:findPath(startPos, endPos, options)
  return self.capabilities.findPath(startPos, endPos, options)
end

function OTClientAdapter:isOnline()
  return self.capabilities.isOnline()
end

function OTClientAdapter:getLevel()
  return self.capabilities.getLevel()
end

function OTClientAdapter:getExperience()
  return self.capabilities.getExperience()
end

function OTClientAdapter:getCapacity()
  return self.capabilities.getCapacity()
end

function OTClientAdapter:getFreeCapacity()
  return self.capabilities.getFreeCapacity()
end

nExBot = nExBot or {}
nExBot.OTClientAdapter = OTClientAdapter.new()

return OTClientAdapter