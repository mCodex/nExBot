-- EquipperService: pure functions and small helpers for rule normalization,
-- condition evaluation, and action planning. Designed to be side-effect free
-- (except when intentionally updating config.activeRule) and easily testable.

local Equipper = {}

-- Normalize a single rule into a compact plan of slot actions
function Equipper.normalizeRule(rule)
  local slots = {}
  for idx, val in ipairs(rule.data or {}) do
    if val == true then
      slots[#slots + 1] = {slotIdx = idx, mode = "unequip"}
    elseif type(val) == "number" and val > 100 then
      slots[#slots + 1] = {slotIdx = idx, mode = "equip", itemId = val}
    end
  end
  return {
    name = rule.name,
    enabled = rule.enabled ~= false,
    visible = rule.visible ~= false,
    mainCondition = rule.mainCondition,
    optionalCondition = rule.optionalCondition,
    mainValue = rule.mainValue,
    optValue = rule.optValue,
    relation = rule.relation or "-",
    slots = slots,
  }
end

function Equipper.normalizeRules(rules)
  local out = {}
  for i = 1, #rules do
    out[#out + 1] = Equipper.normalizeRule(rules[i])
  end
  return out
end

-- Evaluate condition helpers (pure, takes ctx produced by snapshotContext)
local CONDITION_FNS = {
  [1]  = function(ctx, v) return true end,
  [2]  = function(ctx, v) return ctx.monsters > v end,
  [3]  = function(ctx, v) return ctx.monsters < v end,
  [4]  = function(ctx, v) return ctx.hp < v end,
  [5]  = function(ctx, v) return ctx.hp > v end,
  [6]  = function(ctx, v) return ctx.mp < v end,
  [7]  = function(ctx, v) return ctx.mp > v end,
  [8]  = function(ctx, v) return ctx.target and v and ctx.target == v:lower() end,
  [9]  = function(ctx, v) return v and g_keyboard.isKeyPressed(v) end,
  [10] = function(ctx, v) return ctx.paralyzed end,
  [11] = function(ctx, v) return ctx.inPz end,
  [12] = function(ctx, v) return ctx.players > v end,
  [13] = function(ctx, v) return ctx.players < v end,
  [14] = function(ctx, v) return (ctx.danger or 0) > v and ctx.targetbotOn end,
  [15] = function(ctx, v) return isBlackListedPlayerInRange(v) end,
  [16] = function(ctx, v) return ctx.target and table.find(ctx.bosses or {}, ctx.target, true) and true or false end,
  [17] = function(ctx, v) return not ctx.inPz end,
  [18] = function(ctx, v) return ctx.cavebotOn and not ctx.targetbotOn end,
  [19] = function(ctx, v) return ctx.healbotOn end,
  [20] = function(ctx, v) return not ctx.healbotOn end,
}

function Equipper.evalCondition(id, value, ctx)
  local fn = CONDITION_FNS[id]
  if not fn then return false end
  return fn(ctx, value)
end

function Equipper.rulePasses(rule, ctx)
  local mainOk = Equipper.evalCondition(rule.mainCondition, rule.mainValue, ctx)
  if rule.relation == "-" then return mainOk end
  local optOk = Equipper.evalCondition(rule.optionalCondition, rule.optValue, ctx)
  if rule.relation == "and" then return mainOk and optOk end
  if rule.relation == "or" then return mainOk or optOk end
  return mainOk
end

-- Compute next action for a given normalized rule. Two safety helpers must be
-- provided as part of 'helpers' table: slotHasItem, slotHasItemId, isUnsafeToUnequip.
-- This keeps core logic pure and testable.
function Equipper.computeAction(rule, ctx, inventoryIndex, helpers)
  local missing = false
  local slotHasItem = helpers.slotHasItem
  local slotHasItemId = helpers.slotHasItemId
  local isUnsafeToUnequip = helpers.isUnsafeToUnequip

  warn("[EQ][Service] computeAction for rule: " .. tostring(rule.name))

  -- unequip pass
  for _, slotPlan in ipairs(rule.slots) do
    warn("[EQ][Service] checking slot=" .. tostring(slotPlan.slotIdx) .. " mode=" .. tostring(slotPlan.mode) .. " itemId=" .. tostring(slotPlan.itemId))
    if slotPlan.mode == "unequip" then
      local hasItem = slotHasItem(slotPlan.slotIdx)
      warn("[EQ][Service] slotHasItem(" .. tostring(slotPlan.slotIdx) .. ") => " .. tostring(hasItem and true or false))
      if hasItem then
        if isUnsafeToUnequip and isUnsafeToUnequip(ctx) then
          warn("[EQ][Service] unsafe to unequip slot " .. tostring(slotPlan.slotIdx) .. ", deferring")
          missing = true
        else
          warn("[EQ][Service] planning unequip slot " .. tostring(slotPlan.slotIdx))
          return {kind = "unequip", slotIdx = slotPlan.slotIdx}, missing
        end
      end
    end
  end

  -- equip pass
  for _, slotPlan in ipairs(rule.slots) do
    if slotPlan.mode == "equip" and slotPlan.itemId then
      local hasItemId = slotHasItemId(slotPlan.slotIdx, slotPlan.itemId)
      warn("[EQ][Service] slotHasItemId(" .. tostring(slotPlan.slotIdx) .. ", " .. tostring(slotPlan.itemId) .. ") => " .. tostring(hasItemId))
      if not hasItemId then
        -- Check inventory index first, fall back to g_game.findItemInContainers (closed containers)
        local hasItem = false
        if inventoryIndex[slotPlan.itemId] and #inventoryIndex[slotPlan.itemId] > 0 then
          hasItem = true
        else
          if g_game and g_game.findItemInContainers then
            local ok, found = pcall(g_game.findItemInContainers, slotPlan.itemId)
            if ok and found then hasItem = true end
          end
        end
        warn("[EQ][Service] inventory presence for " .. tostring(slotPlan.itemId) .. " => " .. tostring(hasItem))
        if hasItem then
          warn("[EQ][Service] planning equip item " .. tostring(slotPlan.itemId) .. " to slot " .. tostring(slotPlan.slotIdx))
          return {kind = "equip", slotIdx = slotPlan.slotIdx, itemId = slotPlan.itemId}, missing
        else
          warn("[EQ][Service] item " .. tostring(slotPlan.itemId) .. " missing from inventory, mark missing")
          missing = true
        end
      end
    end
  end

  return nil, missing
end

-- Find active rule (prefers config.activeRule index into raw rules), returns
-- normalized rule and its index in the original rules array.
function Equipper.getActiveRule(config)
  local norm = Equipper.normalizeRules(config.rules or {})
  if not norm or #norm == 0 then return nil end
  if config.activeRule and norm[config.activeRule] and norm[config.activeRule].enabled then
    return norm[config.activeRule], config.activeRule
  end
  for i, r in ipairs(norm) do
    if r.enabled then
      -- preserve backward-compatibility but do not force single active rule
      return r, i
    end
  end
  config.activeRule = nil
  return nil
end

-- Return all enabled normalized rules in priority order (pure)
function Equipper.getEnabledRules(config)
  local norm = Equipper.normalizeRules(config.rules or {})
  local out = {}
  for i=1,#norm do
    if norm[i] and norm[i].enabled then
      out[#out+1] = norm[i]
    end
  end
  return out
end

-- Slot / inventory helpers (exposed for runtime use)
local SLOT_ACCESSORS = {
  [1] = getHead,
  [2] = getBody,
  [3] = getLeg,
  [4] = getFeet,
  [5] = getNeck,
  [6] = getLeft,
  [7] = getRight,
  [8] = getFinger,
  [9] = getAmmo,
}

local SLOT_MAP = {
  [1] = 1,  -- head
  [2] = 4,  -- body
  [3] = 7,  -- legs
  [4] = 8,  -- feet
  [5] = 2,  -- neck
  [6] = 6,  -- left hand
  [7] = 5,  -- right hand
  [8] = 9,  -- finger
  [9] = 10, -- ammo
}

local DEFENSIVE_SLOTS = {
  [2] = true,
  [6] = true,
  [7] = true,
}

local function slotHasItem(slotIdx)
  local f = SLOT_ACCESSORS[slotIdx]
  if not f then return nil end
  return f()
end

local function slotHasItemId(slotIdx, itemId)
  local item = slotHasItem(slotIdx)
  if not item then return false end
  local ids = {itemId, getInactiveItemId(itemId), getActiveItemId(itemId)}
  return table.find(ids, item:getId()) and true or false
end

local function buildInventoryIndex()
  local idx = {}
  for _, container in ipairs(getContainers()) do
    local items = container:getItems()
    if items then
      for _, it in ipairs(items) do
        local id = it:getId()
        if not idx[id] then idx[id] = {} end
        table.insert(idx[id], it)
      end
    end
  end
  return idx
end

-- snapshotContext intentionally not provided here; the runtime module owns context creation (depends on `config`).

local SAFETY = {
  minHp = 35,
  maxDanger = 50,
}

local function isUnsafeToUnequip(ctx)
  if ctx.inPz then return false end
  if ctx.hp <= SAFETY.minHp then return true end
  if ctx.danger >= SAFETY.maxDanger then return true end
  return false
end

-- Expose helpers
Equipper.SLOT_MAP = SLOT_MAP
Equipper.slotHasItem = slotHasItem
Equipper.slotHasItemId = slotHasItemId
Equipper.buildInventoryIndex = buildInventoryIndex
Equipper.isUnsafeToUnequip = isUnsafeToUnequip

return Equipper
