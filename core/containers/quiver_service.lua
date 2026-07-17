-- quiver_service.lua
-- Ammo refill service for Paladins.
-- Owns: compatible ammo rules, quiver capacity check, refill loop,
--       serialized acknowledged moves.
-- Requires: QUIVER_READY and AMMO_READY readiness levels.
-- Does NOT own: quiver detection (Quiver), item moves (ClientAdapter via Scheduler).

local Quiver        = dofile("core/containers/quiver.lua")
local ClientAdapter = dofile("core/containers/client_adapter.lua")

local QuiverService = {}

-- Bolt item IDs (cross-bow ammo).
local BOLT_IDS = { 6528, 7363, 3450, 16141, 25758, 14252, 3446, 16142, 35902 }
-- Arrow item IDs (bow ammo).
local ARROW_IDS = { 16143, 763, 761, 7365, 3448, 762, 21470, 7364, 14251, 3447,
                    3449, 15793, 25757, 774, 35901 }
-- Bow item IDs.
local BOW_IDS = { 3350, 31581, 27455, 8027, 20082, 36664, 7438, 28718, 36665,
                  14246, 19362, 35518, 34150, 29417, 9378, 16164, 22866, 12733,
                  8029, 20083, 20084, 8026, 8028, 34088 }
-- Crossbow item IDs.
local XBOW_IDS = { 30393, 3349, 27456, 20085, 16163, 5947, 8021, 14247, 22867,
                   8023, 22711, 19356, 20086, 20087, 34089 }

-- Build O(1) lookups.
local BOW_SET  = {}; for _, id in ipairs(BOW_IDS)   do BOW_SET[id]  = true end
local XBOW_SET = {}; for _, id in ipairs(XBOW_IDS)  do XBOW_SET[id] = true end
local ARROW_SET= {}; for _, id in ipairs(ARROW_IDS) do ARROW_SET[id]= true end
local BOLT_SET = {}; for _, id in ipairs(BOLT_IDS)  do BOLT_SET[id] = true end

-- Refill policies.
QuiverService.Policy = {
  MAINTAIN_MINIMUM = "maintain_minimum",
  FILL_TO_TARGET   = "fill_to_target",
  FILL_TO_CAPACITY = "fill_to_capacity",
  DISABLED         = "disabled",
}

-- Refill outcome reason codes.
QuiverService.Reason = {
  NO_PALADIN        = "NO_PALADIN",
  QUIVER_MISSING    = "QUIVER_MISSING",
  QUIVER_FULL       = "QUIVER_FULL",
  NO_AMMO_SOURCE    = "NO_AMMO_SOURCE",
  INCOMPATIBLE_AMMO = "INCOMPATIBLE_AMMO",
  MOVE_SCHEDULED    = "MOVE_SCHEDULED",
  MOVE_FAILED       = "MOVE_FAILED",
  POLICY_DISABLED   = "POLICY_DISABLED",
  ABOVE_MINIMUM     = "ABOVE_MINIMUM",
  OK                = "OK",
}

local MOVE_COOLDOWN_MS = 400
local MAX_MOVE_RETRIES = 3

function QuiverService.new(registry, scheduler)
  return setmetatable({
    registry       = registry,
    scheduler      = scheduler,
    -- Config.
    policy         = QuiverService.Policy.FILL_TO_TARGET,
    minAmmo        = 50,
    targetAmmo     = 200,
    -- Runtime.
    lastMoveMs     = 0,
    moveInFlight   = false,
    moveRetries    = 0,
    generation     = 0,
    lastReason     = QuiverService.Reason.OK,
  }, { __index = QuiverService })
end

-- Call from Discovery when generation changes.
function QuiverService:setGeneration(gen)
  if gen ~= self.generation then
    self.generation   = gen
    self.moveInFlight = false
    self.moveRetries  = 0
  end
end

-- Main refill entry point.  Returns a reason code string.
function QuiverService:tick()
  if self.policy == QuiverService.Policy.DISABLED then
    return QuiverService.Reason.POLICY_DISABLED
  end
  if not Quiver.isPaladin() then
    return QuiverService.Reason.NO_PALADIN
  end
  if self.moveInFlight then return QuiverService.Reason.MOVE_SCHEDULED end

  local now = os.clock() * 1000
  if (now - self.lastMoveMs) < MOVE_COOLDOWN_MS then
    return QuiverService.Reason.MOVE_SCHEDULED
  end

  -- Find quiver.
  local quiverRoot = Quiver.discoverRoot()
  if not quiverRoot then
    self.lastReason = QuiverService.Reason.QUIVER_MISSING
    return self.lastReason
  end

  -- Get quiver container.
  local quiverContainer = ClientAdapter.getContainerByItem and
    ClientAdapter.getContainerByItem(quiverRoot.item)
  if not quiverContainer then
    -- Try open containers list.
    local containers = ClientAdapter.getContainers() or {}
    for _, c in ipairs(containers) do
      local ci = c.getContainerItem and c:getContainerItem()
      if ci and ci:getId() == quiverRoot.itemType then
        quiverContainer = c
        break
      end
    end
  end
  if not quiverContainer then
    self.lastReason = QuiverService.Reason.QUIVER_MISSING
    return self.lastReason
  end

  -- Count current ammo.
  local currentAmmo = 0
  local ammoType = self:_detectRequiredAmmoType()
  if not ammoType then
    self.lastReason = QuiverService.Reason.INCOMPATIBLE_AMMO
    return self.lastReason
  end

  local items = quiverContainer.getItems and quiverContainer:getItems() or {}
  for _, item in ipairs(items) do
    local ok, id = pcall(function() return item:getId() end)
    if ok and ammoType[id] then
      local ok2, count = pcall(function() return item:getCount() end)
      currentAmmo = currentAmmo + (ok2 and count or 1)
    end
  end

  -- Check if refill is needed.
  local capacity = quiverContainer.getCapacity and quiverContainer:getCapacity() or 200
  local needed   = self:_ammoNeeded(currentAmmo, capacity)
  if needed <= 0 then
    self.lastReason = self.policy == QuiverService.Policy.MAINTAIN_MINIMUM
      and QuiverService.Reason.ABOVE_MINIMUM
      or  QuiverService.Reason.QUIVER_FULL
    return self.lastReason
  end

  -- Find a source using the item index.
  local source = self:_findAmmoSource(ammoType)
  if not source then
    self.lastReason = QuiverService.Reason.NO_AMMO_SOURCE
    return self.lastReason
  end

  -- Schedule the move through the action scheduler.
  self:_scheduleMove(source, quiverContainer, needed)
  self.lastReason = QuiverService.Reason.MOVE_SCHEDULED
  return self.lastReason
end

-- Returns the current refill status for diagnostics.
function QuiverService:getStatus()
  return {
    generation    = self.generation,
    policy        = self.policy,
    minAmmo       = self.minAmmo,
    targetAmmo    = self.targetAmmo,
    moveInFlight  = self.moveInFlight,
    lastReason    = self.lastReason,
    moveRetries   = self.moveRetries,
  }
end

-- ─── Internal ───────────────────────────────────────────────────────────────

-- Returns the ammo type lookup table for the equipped weapon.
function QuiverService:_detectRequiredAmmoType()
  -- Check right-hand weapon.
  local getItem = _G.getClient and _G.getClient() and _G.getClient().getInventoryItem
    or (_G.g_game and _G.g_game.getInventoryItem)
  if not getItem then return nil end

  -- Right-hand slot = 5.
  local weapon = getItem(5)
  if weapon then
    local ok, id = pcall(function() return weapon:getId() end)
    if ok then
      if BOW_SET[id]  then return ARROW_SET end
      if XBOW_SET[id] then return BOLT_SET  end
    end
  end

  -- No weapon → infer from quiver contents.
  local quiverRoot = Quiver.discoverRoot()
  if quiverRoot then
    local containers = ClientAdapter.getContainers() or {}
    for _, c in ipairs(containers) do
      local ci = c.getContainerItem and c:getContainerItem()
      if ci and ci:getId() == quiverRoot.itemType then
        for _, item in ipairs(c:getItems()) do
          local ok2, id2 = pcall(function() return item:getId() end)
          if ok2 then
            if ARROW_SET[id2] then return ARROW_SET end
            if BOLT_SET[id2]  then return BOLT_SET  end
          end
        end
      end
    end
  end
  return nil
end

-- Find an ammo item in open containers that matches the given ammo type set.
function QuiverService:_findAmmoSource(ammoTypeSet)
  -- First try the registry item index.
  if self.registry then
    for ammoId in pairs(ammoTypeSet) do
      local entry = self.registry:findItemByType(ammoId)
      if entry then return entry end
    end
  end

  -- Fallback: scan open containers.
  local containers = ClientAdapter.getContainers() or {}
  for _, c in ipairs(containers) do
    local name = ""
    pcall(function() name = c:getName():lower() end)
    if not name:find("quiver") then
      for slotIdx, item in ipairs(c:getItems()) do
        local ok, id = pcall(function() return item:getId() end)
        if ok and ammoTypeSet[id] then
          return { item = item, containerIdentity = nil, slotIndex = slotIdx }
        end
      end
    end
  end
  return nil
end

-- How much ammo to move based on policy.
function QuiverService:_ammoNeeded(current, capacity)
  if self.policy == QuiverService.Policy.MAINTAIN_MINIMUM then
    if current >= self.minAmmo then return 0 end
    return self.targetAmmo - current
  elseif self.policy == QuiverService.Policy.FILL_TO_TARGET then
    if current >= self.targetAmmo then return 0 end
    return self.targetAmmo - current
  elseif self.policy == QuiverService.Policy.FILL_TO_CAPACITY then
    if current >= capacity then return 0 end
    return capacity - current
  end
  return 0
end

function QuiverService:_scheduleMove(source, destContainer, count)
  if not source or not source.item then return end
  local gen   = self.generation
  local self_ = self
  self.moveInFlight = true
  self.lastMoveMs   = os.clock() * 1000

  if self.scheduler then
    self.scheduler:enqueue({
      type       = "move",
      generation = gen,
      priority   = 3,  -- CRITICAL_AMMO_REFILL
      callback   = function()
        if self_.generation ~= gen then
          self_.moveInFlight = false
          return
        end
        local destPos = destContainer.getSlotPosition and
          destContainer:getSlotPosition(destContainer:getItemsCount())
        if destPos then
          local ok = pcall(function()
            if _G.g_game and _G.g_game.move then
              _G.g_game.move(source.item, destPos, math.min(count, 100))
            end
          end)
          if not ok then
            self_.moveInFlight = false
            self_.moveRetries  = self_.moveRetries + 1
          end
        else
          self_.moveInFlight = false
        end
      end,
    })
  else
    -- No scheduler: direct move.
    local destPos = destContainer.getSlotPosition and
      destContainer:getSlotPosition(destContainer:getItemsCount())
    if destPos and _G.g_game and _G.g_game.move then
      pcall(function() _G.g_game.move(source.item, destPos, math.min(count, 100)) end)
    end
    self.moveInFlight = false
  end
end

-- Call when a move is acknowledged.
function QuiverService:onMoveAck()
  self.moveInFlight = false
  self.moveRetries  = 0
  self.lastMoveMs   = os.clock() * 1000
end

return QuiverService
