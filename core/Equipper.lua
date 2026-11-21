local panelName = "EquipperPanel"
local HealContext = dofile("/core/heal_context.lua")

-- Load EquipperService with error handling
local EquipperService = nil
local serviceLoadOk, serviceResult = pcall(function()
    return dofile("/core/equipper_service.lua")
end)
if serviceLoadOk and serviceResult then
    EquipperService = serviceResult
end

-- STORAGE & STATE (Per-Character with CharacterDB)

-- Default config structure
local DEFAULT_CONFIG = {
    enabled = false,
    rules = {},
    bosses = {},
    activeRule = nil
}

-- Internal state (not persisted)
local _configData = nil
local _saveTimer = nil

-- Schedule save to CharacterDB (debounced)
local function scheduleSave()
    if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then return end
    if not _configData then return end
    if _saveTimer then removeEvent(_saveTimer) end
    _saveTimer = schedule(300, function()
        _saveTimer = nil
        CharacterDB.setModule("equipper", _configData)
    end)
end

-- Force immediate save
local function saveConfig()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() and _configData then
        CharacterDB.setModule("equipper", _configData)
    end
end

-- Initialize config from CharacterDB with migration from legacy storage
local function initConfig()
    local cfg = {}
    
    -- Try to load from CharacterDB first
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        cfg = CharacterDB.getModule("equipper") or {}
        
        -- Migration: if CharacterDB has never been initialized (no _migrated flag)
        -- and legacy storage has data, migrate once
        if not cfg._migrated and storage[panelName] and storage[panelName].rules then
            local legacy = storage[panelName]
            if legacy.rules and #legacy.rules > 0 then
                -- Migrate from legacy storage
                cfg = {
                    enabled = legacy.enabled == true,  -- Explicit boolean check
                    rules = legacy.rules or {},
                    bosses = legacy.bosses or {},
                    activeRule = legacy.activeRule
                }
            end
            -- Mark as migrated so we don't overwrite user deletions
            cfg._migrated = true
            CharacterDB.setModule("equipper", cfg)
        end
    else
        -- Fallback to legacy storage (CharacterDB not ready yet)
        if storage[panelName] then
            cfg = storage[panelName]
        end
    end
    
    -- Ensure all required fields exist with proper defaults
    if cfg.enabled == nil then cfg.enabled = false end
    if not cfg.rules then cfg.rules = {} end
    if not cfg.bosses then cfg.bosses = {} end
    
    _configData = cfg
    return cfg
end

-- Create a proxy that auto-saves to CharacterDB on changes
local function createConfigProxy()
    return setmetatable({}, {
        __index = function(t, k)
            if not _configData then initConfig() end
            return _configData[k]
        end,
        __newindex = function(t, k, v)
            if not _configData then initConfig() end
            _configData[k] = v
            scheduleSave()
        end,
        __pairs = function(t) 
            if not _configData then initConfig() end
            return pairs(_configData) 
        end,
        __ipairs = function(t) 
            if not _configData then initConfig() end
            return ipairs(_configData) 
        end,
    })
end

-- Initialize config now
initConfig()
local config = createConfigProxy()

-- Non-blocking equipment manager state
local EquipState = {
    lastEquipAction = 0,
    EQUIP_COOLDOWN = 600,       -- ms between equip actions (safe value)
    CHECK_INTERVAL = 500,       -- ms between condition checks (throttle)
    lastCheckTime = 0,          -- Last time we ran a full check
    pendingCheck = false,       -- Flag for debounced check
    missingItem = false,
    lastRule = nil,
    correctEq = false,
    needsEquipCheck = true,
    rulesCache = nil,           -- Cached rules for macro iteration
    rulesCacheDirty = true,     -- Flag to rebuild cache
    normalizedRules = nil,
    normalizedDirty = true,
    inventoryCache = nil,       -- Cached inventory index
    inventoryCacheTime = 0,     -- When inventory was last cached
    INVENTORY_CACHE_TTL = 300,  -- ms before inventory cache expires
}

-- CACHE MANAGEMENT

-- Invalidate rules cache when rules change
local function invalidateRulesCache()
  EquipState.rulesCacheDirty = true
  EquipState.needsEquipCheck = true
  EquipState.correctEq = false
    EquipState.normalizedDirty = true
end

-- Get cached rules (avoids repeated getChildren calls in macro)
local function getCachedRules()
  if EquipState.rulesCacheDirty or not EquipState.rulesCache then
    EquipState.rulesCache = config.rules
    EquipState.rulesCacheDirty = false
  end
  return EquipState.rulesCache
end

-- RULE NORMALIZATION (precompute slot plans)

-- Delegate normalization to EquipperService for testability and clarity
local function normalizeRule(rule)
  return EquipperService.normalizeRule(rule)
end

local function getNormalizedRules()
    if EquipState.normalizedDirty or not EquipState.normalizedRules then
        local raw = getCachedRules() or {}
        if EquipperService and EquipperService.normalizeRules then
            EquipState.normalizedRules = EquipperService.normalizeRules(raw)
        else
            -- EquipperService missing; using fallback normalization
            local norm = {}
            for i = 1, #raw do
                -- basic fallback normalization
                local r = raw[i]
                local slots = {}
                for idx, val in ipairs(r.data or {}) do
                    if val == true then
                        slots[#slots + 1] = {slotIdx = idx, mode = "unequip"}
                    elseif type(val) == "number" and val > 100 then
                        slots[#slots + 1] = {slotIdx = idx, mode = "equip", itemId = val}
                    end
                end
                norm[#norm + 1] = {
                    name = r.name,
                    enabled = r.enabled ~= false,
                    visible = r.visible ~= false,
                    mainCondition = r.mainCondition,
                    optionalCondition = r.optionalCondition,
                    mainValue = r.mainValue,
                    optValue = r.optValue,
                    relation = r.relation or "-",
                    slots = slots,
                }
            end
            EquipState.normalizedRules = norm
        end
        EquipState.normalizedDirty = false
    end
    return EquipState.normalizedRules
end

-- Get the currently active rule (first enabled rule by index)
-- Return enabled rules in priority order (pure)
local function getEnabledRules()
    if EquipperService and EquipperService.getEnabledRules then
        return EquipperService.getEnabledRules(config)
    end
    local rules = getNormalizedRules() or {}
    local out = {}
    for i, r in ipairs(rules) do
        if r.enabled then out[#out + 1] = r end
    end
    return out
end

-- Delayed re-sync to ensure CharacterDB is ready
-- (In case the player wasn't fully available at init time)
schedule(500, function()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        -- Reinitialize config from CharacterDB
        initConfig()
        invalidateRulesCache()
    end
end)

-- SLOT / INVENTORY HELPERS (pure-ish, cached per tick)

-- Delegate slot/inventory/context helpers to EquipperService when available
local SLOT_MAP = (EquipperService and EquipperService.SLOT_MAP) or {
    [1] = 1, [2] = 4, [3] = 7, [4] = 8, [5] = 2, [6] = 6, [7] = 5, [8] = 9, [9] = 10,
}

local slotHasItem = EquipperService and EquipperService.slotHasItem or function(slotIdx)
    local f = ({[1]=getHead,[2]=getBody,[3]=getLeg,[4]=getFeet,[5]=getNeck,[6]=getLeft,[7]=getRight,[8]=getFinger,[9]=getAmmo})[slotIdx]
    if not f then return nil end
    return f()
end

local slotHasItemId = EquipperService and EquipperService.slotHasItemId or function(slotIdx, itemId)
    local item = slotHasItem(slotIdx)
    if not item then return false end
    local ids = {itemId, getInactiveItemId(itemId), getActiveItemId(itemId)}
    return table.find(ids, item:getId()) and true or false
end

local buildInventoryIndex = EquipperService and EquipperService.buildInventoryIndex or function()
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

local snapshotContext = EquipperService and EquipperService.snapshotContext or function()
    return {
        hp = hppercent(), mp = manapercent(), monsters = (getMonsters and getMonsters()) or 0, players = (getPlayers and getPlayers()) or 0,
        target = (target and target()) and target():getName():lower() or nil, inPz = isInPz and isInPz() or false, paralyzed = isParalyzed and isParalyzed() or false,
        danger = (TargetBot and TargetBot.Danger and TargetBot.Danger()) or 0,
        cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
        targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
        healbotOn = (storage["healbot"] and storage["healbot"][1] and storage["healbot"][1].enabled) or false,
        bosses = config.bosses or {},
    }
end

local isUnsafeToUnequip = EquipperService and EquipperService.isUnsafeToUnequip or function(ctx)
    if ctx.inPz then return false end
    -- HP-based unequip safety disabled per user request (allow unequip regardless of HP)
    if ctx.danger >= 50 then return true end
    return false
end

local function unequipSlot(slotIdx)
    local item = slotHasItem(slotIdx)
    if not item then return false end
    -- Preferred: move equipped item from inventory slot to first available backpack
    
    local dest
    for _, container in ipairs(getContainers()) do
        if not containerIsFull(container) then
            dest = container
            break
        end
    end
    if not dest then
        
        return false
    end
    local pos = dest:getSlotPosition(dest:getItemsCount())
    local ok = g_game.move(item, pos, item:getCount())
    
    return ok
end

local function equipSlot(slotIdx, itemId)
    local mappedSlot = SLOT_MAP[slotIdx] or slotIdx
    

    -- Try direct equip API first (non-blocking request)
    local triedEquipApi = false
    if g_game and g_game.equipItemId then
        triedEquipApi = true
        local ok = pcall(function() g_game.equipItemId(itemId) end)
        
        -- small chance server synchronizes instantly; re-check
        if slotHasItemId(slotIdx, itemId) then
            
            return true
        end
    end

    -- Fallback: try g_game.findItemInContainers first (may find in closed containers)
    local found = nil
    if g_game and g_game.findItemInContainers then
        pcall(function()
            local f = g_game.findItemInContainers(itemId)
            if f then found = f end
        end)
    end
    if not found then
        for _, container in ipairs(getContainers()) do
            for _, it in ipairs(container:getItems() or {}) do
                if it:getId() == itemId then
                    found = it
                    break
                end
            end
            if found then break end
        end
    end
    if not found then
        
            -- item not found in open containers
            return false
    end
    local ok2 = g_game.move(found, {x = 65535, y = mappedSlot, z = 0}, found:getCount())
    
    return slotHasItemId(slotIdx, itemId) or ok2
end

-- CONDITIONS (table-driven)

-- Delegate condition evaluation to EquipperService when available, fallback to local map
local LOCAL_CONDITIONS = {
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
    [16] = function(ctx, v) return ctx.target and table.find(config.bosses, ctx.target, true) and true or false end,
    [17] = function(ctx, v) return not ctx.inPz end,
    [18] = function(ctx, v) return ctx.cavebotOn and not ctx.targetbotOn end,
    [19] = function(ctx, v) return ctx.healbotOn end,
    [20] = function(ctx, v) return not ctx.healbotOn end,
}

local function evalCondition(id, value, ctx)
    if EquipperService and EquipperService.evalCondition then
        return EquipperService.evalCondition(id, value, ctx)
    end
    local fn = LOCAL_CONDITIONS[id]
    if not fn then return false end
    return fn(ctx, value)
end

local function rulePasses(rule, ctx)
    if EquipperService and EquipperService.rulePasses then
        return EquipperService.rulePasses(rule, ctx)
    end
    -- fallback with debug info
    local mainOk = evalCondition(rule.mainCondition, rule.mainValue, ctx)
    if rule.relation == "-" then return mainOk end
    local optOk = evalCondition(rule.optionalCondition, rule.optValue, ctx)
    if rule.relation == "and" then return mainOk and optOk end
    if rule.relation == "or" then return mainOk or optOk end
    return mainOk
end

-- ACTION PLANNING (pure decision-making)

local function computeAction(rule, ctx, inventoryIndex)
    -- Delegate pure decision making to service for testability/consistency
    if EquipperService and EquipperService.computeAction then
        return EquipperService.computeAction(rule, ctx, inventoryIndex, {
            slotHasItem = slotHasItem,
            slotHasItemId = slotHasItemId,
            isUnsafeToUnequip = isUnsafeToUnequip,
        })
    end
    
    -- FALLBACK: If service missing, implement computeAction locally
    local missing = false
    
    -- unequip pass
    for _, slotPlan in ipairs(rule.slots or {}) do
        if slotPlan.mode == "unequip" then
            local hasItem = slotHasItem(slotPlan.slotIdx)
            if hasItem then
                if isUnsafeToUnequip and isUnsafeToUnequip(ctx) then
                    missing = true
                else
                    return {kind = "unequip", slotIdx = slotPlan.slotIdx}, missing
                end
            end
        end
    end
    
    -- equip pass
    for _, slotPlan in ipairs(rule.slots or {}) do
        if slotPlan.mode == "equip" and slotPlan.itemId then
            local hasItemId = slotHasItemId(slotPlan.slotIdx, slotPlan.itemId)
            if not hasItemId then
                -- Check inventory index first
                local hasItem = false
                if inventoryIndex[slotPlan.itemId] and #inventoryIndex[slotPlan.itemId] > 0 then
                    hasItem = true
                else
                    -- Try g_game.findItemInContainers
                    if g_game and g_game.findItemInContainers then
                        local ok, found = pcall(g_game.findItemInContainers, slotPlan.itemId)
                        if ok and found then
                            hasItem = true
                        end
                    end
                end
                if hasItem then
                    return {kind = "equip", slotIdx = slotPlan.slotIdx, itemId = slotPlan.itemId}, missing
                else
                    missing = true
                end
            end
        end
    end
    
    return nil, missing
end

-- EVENT SUBSCRIPTIONS - Listen for condition changes

-- Helper to trigger equipment re-check (just sets flag, no immediate processing)
local function triggerEquipCheck()
    EquipState.needsEquipCheck = true
    EquipState.correctEq = false
end

-- Get cached inventory index (avoids rebuilding on every check)
local function getCachedInventoryIndex()
    local timeSinceCache = now - EquipState.inventoryCacheTime
    if not EquipState.inventoryCache or timeSinceCache > EquipState.INVENTORY_CACHE_TTL then
        EquipState.inventoryCache = buildInventoryIndex()
        EquipState.inventoryCacheTime = now
    end
    return EquipState.inventoryCache
end

-- Invalidate inventory cache (call when items change)
local function invalidateInventoryCache()
    EquipState.inventoryCache = nil
    EquipState.inventoryCacheTime = 0
end

-- Throttled equipment check - only runs once per CHECK_INTERVAL
local function throttledEquipCheck()
    if not config.enabled then return end
    
    -- Throttle: Skip if we checked too recently
    local timeSinceCheck = now - EquipState.lastCheckTime
    if timeSinceCheck < EquipState.CHECK_INTERVAL then
        return
    end
    
    -- Skip if on action cooldown
    local timeSinceAction = now - EquipState.lastEquipAction
    if timeSinceAction < EquipState.EQUIP_COOLDOWN then
        return
    end
    
    local rules = getEnabledRules()
    if not rules or #rules == 0 then return end
    
    -- Update last check time
    EquipState.lastCheckTime = now
    
    local ctx = snapshotContext()
    local inventoryIndex = getCachedInventoryIndex()
    
    for _, rule in ipairs(rules) do
        if rulePasses(rule, ctx) then
            local action, missing = computeAction(rule, ctx, inventoryIndex)
            if action then
                if action.kind == "unequip" then
                    if unequipSlot(action.slotIdx) then
                        EquipState.lastEquipAction = now
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        invalidateInventoryCache()
                        return
                    end
                elseif action.kind == "equip" then
                    if equipSlot(action.slotIdx, action.itemId) then
                        EquipState.lastEquipAction = now
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        invalidateInventoryCache()
                        return
                    end
                end
            end
        end
    end
end

-- Subscribe via EventBus if available (just set flag, throttled check handles the rest)
if EventBus then
    EventBus.on("player:mana", function() triggerEquipCheck() end, 100)
    EventBus.on("player:health", function() triggerEquipCheck() end, 100)
    EventBus.on("target:change", function() triggerEquipCheck() end, 100)
    EventBus.on("player:pz", function() triggerEquipCheck() end, 100)
    EventBus.on("player:states", function() triggerEquipCheck() end, 100)
else
    -- FALLBACK: Use native OTC callbacks only if EventBus unavailable
    if onManaChange then onManaChange(function() triggerEquipCheck() end) end
    if onHealthChange then onHealthChange(function() triggerEquipCheck() end) end
    if onTargetChange then onTargetChange(function() triggerEquipCheck() end) end
    if onStatesChange then onStatesChange(function() triggerEquipCheck() end) end
end

-- MAIN EQUIPMENT MACRO
-- Single point of equipment checking - runs throttled checks

EquipManager = macro(300, function()
    if not config.enabled then return end

    -- Run the throttled check (respects cooldowns internally)
    throttledEquipCheck()
end)

local SLOT_NAMES = { "Head", "Body", "Legs", "Feet", "Neck", "Left hand", "Right hand", "Finger", "Ammo" }

nExBot.Equipper = {
    isEnabled = function() return config.enabled == true end,
    setEnabled = function(enabled)
        config.enabled = enabled == true
        saveConfig()
        triggerEquipCheck()
    end,
    show = function() end,
    getRules = function() return config.rules end,
    getSlots = function()
        local slots = {}
        for i = 1, #SLOT_NAMES do
            local item = slotHasItem(i)
            slots[#slots + 1] = { index = i, name = SLOT_NAMES[i], itemId = item and item:getId() or 0 }
        end
        return slots
    end,
    getBosses = function()
        local out = {}
        for i = 1, #(config.bosses or {}) do out[i] = config.bosses[i] end
        return out
    end,
    addBoss = function(name)
        if type(name) ~= "string" or name:len() == 0 then return false, "Enter a boss name." end
        if table.find(config.bosses, name:lower(), true) then return false, "That boss is already listed." end
        table.insert(config.bosses, name)
        saveConfig()
        return true
    end,
    removeBoss = function(name)
        local index = table.find(config.bosses, name)
        if not index then return false end
        table.remove(config.bosses, index)
        saveConfig()
        return true
    end,
    addRule = function(rule)
        if not rule or type(rule.name) ~= "string" or rule.name:len() == 0 then return false, "Enter a rule name." end
        local data = {}
        for i = 1, #SLOT_NAMES do data[i] = rule.data and rule.data[i] or false end
        local entry = {
            name = rule.name, data = data, enabled = rule.enabled ~= false, visible = rule.visible ~= false,
            mainCondition = rule.mainCondition or 1, optionalCondition = rule.optionalCondition or 2,
            mainValue = rule.mainValue, optValue = rule.optValue, relation = rule.relation or "-",
        }
        local index
        for i, v in ipairs(config.rules) do
            if v.name:lower() == entry.name:lower() then index = i; break end
        end
        if index then config.rules[index] = entry else table.insert(config.rules, entry) end
        config.activeRule = nil
        invalidateRulesCache()
        saveConfig()
        return true
    end,
    getProjection = function()
        local rows = {}
        for index, rule in ipairs(config.rules or {}) do
            local itemId
            for _, value in ipairs(rule.data or {}) do
                if type(value) == "number" and value > 100 then itemId = value; break end
            end
            rows[#rows + 1] = {
                index = index, name = rule.name or ("Rule " .. index), enabled = rule.enabled ~= false,
                itemId = itemId, mainCondition = rule.mainCondition, mainValue = rule.mainValue,
                optionalCondition = rule.optionalCondition, optValue = rule.optValue, relation = rule.relation,
                revision = index .. ":" .. tostring(rule.enabled) .. ":" .. tostring(itemId),
            }
        end
        return { enabled = config.enabled == true, activeRule = config.activeRule, rows = rows }
    end,
    toggleRule = function(index)
        local rule = config.rules and config.rules[index]
        if not rule then return false end
        rule.enabled = not rule.enabled
        invalidateRulesCache()
        saveConfig()
        return true
    end,
    moveRule = function(index, direction)
        local rules = config.rules or {}
        local destination = index + (direction == "up" and -1 or direction == "down" and 1 or 0)
        if not rules[index] or destination < 1 or destination > #rules or destination == index then return false end
        rules[index], rules[destination] = rules[destination], rules[index]
        invalidateRulesCache()
        saveConfig()
        return true
    end,
    removeRule = function(index)
        if not config.rules or not config.rules[index] then return false end
        table.remove(config.rules, index)
        invalidateRulesCache()
        saveConfig()
        return true
    end,
}

-- EVENT-DRIVEN EQUIPMENT MANAGEMENT
-- Listen to equipment changes to invalidate cache

if EventBus then
    EventBus.on("equipment:change", function(slotId, slotName, currentId, lastId, item)
        -- Invalidate state on equipment change
        EquipState.needsEquipCheck = true
        EquipState.correctEq = false
        invalidateInventoryCache()
    end, 50)
end

-- End of Equipper module
