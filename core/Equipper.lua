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

-- ============================================================================
-- UI SETUP
-- ============================================================================

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: switch
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('EQ Manager')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

-- ============================================================================
-- STORAGE & STATE (Per-Character with CharacterDB)
-- ============================================================================

-- Default config structure
local DEFAULT_CONFIG = {
    enabled = false,
    rules = {},
    bosses = {},
    activeRule = nil
}

-- Initialize config from CharacterDB with migration from legacy storage
local function initConfig()
    local config
    
    -- Try to load from CharacterDB first
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        config = CharacterDB.getModule("equipper")
        
        -- Migration: if CharacterDB is empty but legacy storage has data
        if (not config.rules or #config.rules == 0) and storage[panelName] and storage[panelName].rules then
            local legacy = storage[panelName]
            if legacy.rules and #legacy.rules > 0 then
                -- Migrate from legacy storage
                config = {
                    enabled = legacy.enabled or false,
                    rules = legacy.rules or {},
                    bosses = legacy.bosses or {},
                    activeRule = legacy.activeRule
                }
                CharacterDB.setModule("equipper", config)
                -- Note: We don't clear legacy storage to preserve data for other characters
            end
        end
    else
        -- Fallback to legacy storage (CharacterDB not ready yet)
        if not storage[panelName] or not storage[panelName].bosses then
            storage[panelName] = DEFAULT_CONFIG
        end
        config = storage[panelName]
    end
    
    -- Ensure all required fields exist
    config.enabled = config.enabled or false
    config.rules = config.rules or {}
    config.bosses = config.bosses or {}
    config.activeRule = config.activeRule or nil
    
    return config
end

-- Create a proxy that auto-saves to CharacterDB on changes
local function createConfigProxy(initialConfig)
    local _data = initialConfig
    local _saveTimer = nil
    
    local function scheduleSave()
        if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then return end
        if _saveTimer then removeEvent(_saveTimer) end
        _saveTimer = scheduleEvent(function()
            _saveTimer = nil
            CharacterDB.setModule("equipper", _data)
        end, 300)
    end
    
    -- Expose data directly (for read operations)
    -- Modifications should trigger save via explicit call
    return setmetatable({}, {
        __index = function(t, k)
            return _data[k]
        end,
        __newindex = function(t, k, v)
            _data[k] = v
            scheduleSave()
        end,
        -- Expose raw data for ipairs/pairs
        __pairs = function(t) return pairs(_data) end,
        __ipairs = function(t) return ipairs(_data) end,
    })
end

local config = createConfigProxy(initConfig())

-- Force save function (call after modifying nested tables like rules/bosses)
local function saveConfig()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        CharacterDB.setModule("equipper", {
            enabled = config.enabled,
            rules = config.rules,
            bosses = config.bosses,
            activeRule = config.activeRule
        })
    end
end

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

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

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

-- ============================================================================
-- RULE NORMALIZATION (precompute slot plans)
-- ============================================================================

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

ui.switch:setOn(config.enabled)
ui.switch.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

local conditions = { -- always add new conditions at the bottom
    "Item is available and not worn.", -- nothing 1
    "Monsters around is more than: ", -- spinbox 2
    "Monsters around is less than: ", -- spinbox 3
    "Health precent is below:", -- spinbox 4
    "Health precent is above:", -- spinbox 5
    "Mana precent is below:", -- spinbox 6
    "Mana precent is above:", -- spinbox 7
    "Target name is:", -- BotTextEdit 8
    "Hotkey is being pressed:", -- BotTextEdit 9
    "Player is paralyzed", -- nothing 10
    "Player is in protection zone", -- nothing 11
    "Players around is more than:", -- spinbox 12
    "Players around is less than:", -- spinbox 13
    "TargetBot Danger is Above:", -- spinbox 14
    "Blacklist player in range (sqm)", -- spinbox 15
    "Target is Boss", -- nothing 16
    "Player is NOT in protection zone", -- nothing 17
    "CaveBot is ON, TargetBot is OFF", -- nothing 18
    "HealBot is enabled", -- nothing 19
    "HealBot is disabled" -- nothing 20
}

local conditionNumber = 1
local optionalConditionNumber = 2

local mainWindow = UI.createWindow("EquipWindow")
mainWindow:hide()

ui.setup.onClick = function()
    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
end

local inputPanel = mainWindow.inputPanel
local listPanel = mainWindow.listPanel
local namePanel = mainWindow.profileName
local eqPanel = mainWindow.setup
local bossPanel = mainWindow.bossPanel

local slotWidgets = {eqPanel.head, eqPanel.body, eqPanel.legs, eqPanel.feet, eqPanel.neck, eqPanel["left-hand"], eqPanel["right-hand"], eqPanel.finger, eqPanel.ammo} -- back is disabled

local function setCondition(first, n)
    local widget
    local spinBox 
    local textEdit

    if first then
        widget = inputPanel.condition.description.text
        spinBox = inputPanel.condition.spinbox
        textEdit = inputPanel.condition.text
    else
        widget = inputPanel.optionalCondition.description.text
        spinBox = inputPanel.optionalCondition.spinbox
        textEdit = inputPanel.optionalCondition.text
    end

    -- reset values after change
    spinBox:setValue(0)
    textEdit:setText('')

    if n == 1 or n == 10 or n == 11 or n == 16 or n == 17 or n == 18 or n == 19 or n == 20 then
        spinBox:hide()
        textEdit:hide()
    elseif n == 9 or n == 8 then
        spinBox:hide()
        textEdit:show()
        if n == 9 then
            textEdit:setWidth(75)
        else
            textEdit:setWidth(200)
        end
    else
        spinBox:show()
        textEdit:hide()
    end
    widget:setText(conditions[n])
end

local function resetFields()
    conditionNumber = 1
    optionalConditionNumber = 2
    setCondition(false, optionalConditionNumber)
    setCondition(true, conditionNumber)
    for i, widget in ipairs(slotWidgets) do
        widget:setItemId(0)
        widget:setChecked(false)
    end
    local children = listPanel.list:getChildren()
    for i = 1, #children do
        children[i].display = false
    end
    namePanel.profileName:setText("")
    inputPanel.condition.text:setText('')
    inputPanel.condition.spinbox:setValue(0)
    inputPanel.useSecondCondition:setText('-')
    inputPanel.optionalCondition.text:setText('')
    inputPanel.optionalCondition.spinbox:setValue(0)
    inputPanel.optionalCondition:hide()
    bossPanel:hide()
    listPanel:show()
    mainWindow.bossList:setText('Boss List')
    bossPanel.name:setText('')
end
resetFields()

mainWindow.closeButton.onClick = function()
    resetFields()
    mainWindow:hide()
end

inputPanel.optionalCondition:hide()
inputPanel.useSecondCondition.onOptionChange = function(widget, option, data)
    if option ~= "-" then
        inputPanel.optionalCondition:show()
    else
        inputPanel.optionalCondition:hide()
    end
end

-- add default text & windows
setCondition(true, 1)
setCondition(false, 2)

-- in/de/crementation buttons
inputPanel.condition.nex.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == max then
            if optionalConditionNumber == 1 then
                conditionNumber = 2
            else
                conditionNumber = 1
            end
        else
            local futureNumber = conditionNumber + 1
            local safeFutureNumber = conditionNumber + 2 > max and 1 or conditionNumber + 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == max and 1 or conditionNumber + 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == max and 1 or optionalConditionNumber + 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.condition.pre.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == 1 then
            if optionalConditionNumber == max then
                conditionNumber = max-1
            else
                conditionNumber = max
            end
        else
            local futureNumber = conditionNumber - 1
            local safeFutureNumber = conditionNumber - 2 < 1 and max or conditionNumber - 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == 1 and max or conditionNumber - 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == 1 and max or optionalConditionNumber - 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.optionalCondition.nex.onClick = function()
    local max = #conditions

    if optionalConditionNumber == max then
        if conditionNumber == 1 then
            optionalConditionNumber = 2
        else
            optionalConditionNumber = 1
        end
    else
        local futureNumber = optionalConditionNumber + 1
        local safeFutureNumber = optionalConditionNumber + 2 > max and 1 or optionalConditionNumber + 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

inputPanel.optionalCondition.pre.onClick = function()
    local max = #conditions

    if optionalConditionNumber == 1 then
        if conditionNumber == max then
            optionalConditionNumber = max-1
        else
            optionalConditionNumber = max
        end
    else
        local futureNumber = optionalConditionNumber - 1
        local safeFutureNumber = optionalConditionNumber - 2 < 1 and max or optionalConditionNumber - 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

listPanel.up.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules

    if n <= 1 then return end  -- Can't move up if already at top
    
    t[n], t[n-1] = t[n-1], t[n]
    
    -- Refresh entire list to fix ruleIndex references
    invalidateRulesCache()
    refreshRules()
    
    -- Re-focus the moved item (now at n-1)
    local children = listPanel.list:getChildren()
    if children[n-1] then
        listPanel.list:focusChild(children[n-1])
        listPanel.list:ensureChildVisible(children[n-1])
    end
    
    -- Update button states
    listPanel.up:setEnabled(n-1 > 1)
    listPanel.down:setEnabled(true)
end

listPanel.down.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()    
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules
    local count = #t

    if n >= count then return end  -- Can't move down if already at bottom
    
    t[n], t[n+1] = t[n+1], t[n]
    
    -- Refresh entire list to fix ruleIndex references
    invalidateRulesCache()
    refreshRules()
    
    -- Re-focus the moved item (now at n+1)
    local children = listPanel.list:getChildren()
    if children[n+1] then
        listPanel.list:focusChild(children[n+1])
        listPanel.list:ensureChildVisible(children[n+1])
    end
    
    -- Update button states
    listPanel.up:setEnabled(true)
    listPanel.down:setEnabled(n+1 < count)
end

eqPanel.cloneEq.onClick = function(widget)
    eqPanel.head:setItemId(getHead() and getHead():getId() or 0)
    eqPanel.body:setItemId(getBody() and getBody():getId() or 0)
    eqPanel.legs:setItemId(getLeg() and getLeg():getId() or 0)
    eqPanel.feet:setItemId(getFeet() and getFeet():getId() or 0)  
    eqPanel.neck:setItemId(getNeck() and getNeck():getId() or 0)   
    eqPanel["left-hand"]:setItemId(getLeft() and getLeft():getId() or 0)
    eqPanel["right-hand"]:setItemId(getRight() and getRight():getId() or 0)
    eqPanel.finger:setItemId(getFinger() and getFinger():getId() or 0)    
    eqPanel.ammo:setItemId(getAmmo() and getAmmo():getId() or 0)    
end

eqPanel.default.onClick = resetFields

-- buttons disabled by default
listPanel.up:setEnabled(false)
listPanel.down:setEnabled(false)

-- correct background image
for i, widget in ipairs(slotWidgets) do
    widget:setTooltip("Right click to set as slot to unequip")
    widget.onItemChange = function(widget)
        local selfId = widget:getItemId()
        widget:setOn(selfId > 100)
        if widget:isChecked() then
            widget:setChecked(selfId < 100)
        end
    end
    widget.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == 2 then
            local clearItem = widget:isChecked() == false
            widget:setChecked(not widget:isChecked())
            if clearItem then
                widget:setItemId(0)
            end
        end
    end
end

inputPanel.condition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.condition.nex.onClick()
    else
        inputPanel.condition.pre.onClick()
    end
end

inputPanel.optionalCondition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.optionalCondition.nex.onClick()
    else
        inputPanel.optionalCondition.pre.onClick()
    end
end

namePanel.profileName.onTextChange = function(widget, text)
    local button = inputPanel.add
    text = text:lower()
    
    -- Check against config.rules directly (not UI children)
    local isOverwrite = false
    for i = 1, #config.rules do
        if config.rules[i].name:lower() == text then
            isOverwrite = true
            break
        end
    end
    
    button:setText(isOverwrite and "Overwrite" or "Add Rule")
    button:setTooltip(isOverwrite and ("Overwrite existing rule named: " .. text) or ("Add new rule to the list: " .. text))
end

-- Populate Equipment Setup slots when editing a rule (double-click)
local function loadRuleToSlots(data)
    for i, value in ipairs(data) do
        local widget = slotWidgets[i]
        if value == false then
            widget:setChecked(false)
            widget:setItemId(0)
        elseif value == true then
            widget:setChecked(true)
            widget:setItemId(0)
        else
            widget:setChecked(false)
            widget:setItemId(value)       
        end
    end
end

-- ============================================================================
-- RULES LIST UI (Fixed - proper sync between UI and config.rules)
-- ============================================================================

-- Forward declare refreshRules
local refreshRules

-- Create or update a single rule widget - uses rule reference directly
local function createRuleWidget(list, rule, index)
  local widget = UI.createWidget('Rule', list)
  
  widget:setId("rule_" .. index)
  widget:setText(rule.name)
  
  -- Store index, not a copy of rule data - always access config.rules[index] directly
  widget.ruleIndex = index
  
  -- Update visual state
  widget.visible:setColor(rule.visible and "green" or "red")
  widget.enabled:setChecked(rule.enabled and true or false)
  
  -- Event handlers
  widget.remove.onClick = function()
    local idx = widget.ruleIndex
    if idx and config.rules[idx] then
      table.remove(config.rules, idx)
      if config.activeRule and config.activeRule > #config.rules then
        config.activeRule = nil
      end
    end
    listPanel.up:setEnabled(false)
    listPanel.down:setEnabled(false)
    invalidateRulesCache()
    refreshRules()
    saveConfig()  -- Persist to CharacterDB
  end

  widget.visible.onClick = function()
    local idx = widget.ruleIndex
    if idx and config.rules[idx] then
      config.rules[idx].visible = not config.rules[idx].visible
      widget.visible:setColor(config.rules[idx].visible and "green" or "red")
      saveConfig()  -- Persist to CharacterDB
    end
  end

  widget.enabled.onClick = function()
    local idx = widget.ruleIndex
    if idx and config.rules[idx] then
      config.rules[idx].enabled = not config.rules[idx].enabled
      widget.enabled:setChecked(config.rules[idx].enabled and true or false)
      invalidateRulesCache()
      saveConfig()  -- Persist to CharacterDB
    end
  end

  widget.onDoubleClick = function(w)
    local idx = w.ruleIndex
    if not idx or not config.rules[idx] then return end
    local ruleData = config.rules[idx]
    
    w.display = true
    loadRuleToSlots(ruleData.data)
    conditionNumber = ruleData.mainCondition
    optionalConditionNumber = ruleData.optionalCondition
    setCondition(false, optionalConditionNumber)
    setCondition(true, conditionNumber)
    inputPanel.useSecondCondition:setOption(ruleData.relation)
    namePanel.profileName:setText(ruleData.name)

    if type(ruleData.mainValue) == "string" then
      inputPanel.condition.text:setText(ruleData.mainValue)
    elseif type(ruleData.mainValue) == "number" then
      inputPanel.condition.spinbox:setValue(ruleData.mainValue)
    end

    if type(ruleData.optValue) == "string" then
      inputPanel.optionalCondition.text:setText(ruleData.optValue)
    elseif type(ruleData.optValue) == "number" then
      inputPanel.optionalCondition.spinbox:setValue(ruleData.optValue)
    end
  end
  
  widget.onClick = function()
    local panel = listPanel
    local childCount = #panel.list:getChildren()
    local focusedChild = panel.list:getFocusedChild()
    local focusedIndex = focusedChild and panel.list:getChildIndex(focusedChild) or 0
    
    if childCount == 1 then
      panel.up:setEnabled(false)
      panel.down:setEnabled(false)
    elseif focusedIndex == 1 then
      panel.up:setEnabled(false)
      panel.down:setEnabled(true)
    elseif focusedIndex == childCount then
      panel.up:setEnabled(true)
      panel.down:setEnabled(false)
    else
      panel.up:setEnabled(true)
      panel.down:setEnabled(true)
    end
  end
  
  return widget
end

refreshRules = function()
  local list = listPanel.list
  
  -- Clear all existing widgets to avoid stale references
  local existingChildren = list:getChildren()
  for i = #existingChildren, 1, -1 do
    existingChildren[i]:destroy()
  end
  
  -- Create fresh widgets for each rule
  for i, rule in ipairs(config.rules) do
    createRuleWidget(list, rule, i)
  end
  
  -- Reset up/down button states
  listPanel.up:setEnabled(false)
  listPanel.down:setEnabled(false)
  
  -- Invalidate macro cache
  invalidateRulesCache()
end
refreshRules()

inputPanel.add.onClick = function(widget)
    local mainVal
    local optVal
    local t = {}
    local relation = inputPanel.useSecondCondition:getText()
    local profileName = namePanel.profileName:getText()
    if profileName:len() == 0 then
        return warn("Please fill profile name!")
    end

    for i, widget in ipairs(slotWidgets) do
        local checked = widget:isChecked()
        local id = widget:getItemId()

        if checked then
            table.insert(t, true) -- unequip selected slot
        elseif id then
            table.insert(t, id) -- equip selected item
        else
            table.insert(t, false) -- ignore slot
        end
    end

    if conditionNumber == 1 then
        mainVal = nil
    elseif conditionNumber == 8 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[nExBot Equipper] Please fill the name of the creature.")
        end
    elseif conditionNumber == 9 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[nExBot Equipper] Please set correct hotkey.")
        end
    else
        mainVal = inputPanel.condition.spinbox:getValue()
    end

    if relation ~= "-" then
        if optionalConditionNumber == 1 then
            optVal = nil
        elseif optionalConditionNumber == 8 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[nExBot Equipper] Please fill the name of the creature.")
            end
        elseif optionalConditionNumber == 9 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[nExBot Equipper] Please set correct hotkey.")
            end
        else
            optVal = inputPanel.optionalCondition.spinbox:getValue()
        end
    end

    local index
    for i, v in ipairs(config.rules) do
        if v.name == profileName then
            index = i   -- search if there's already rule with this name
        end
    end

    local ruleData = {
        name = profileName, 
        data = t,
        enabled = true,
        visible = true,
        mainCondition = conditionNumber,
        optionalCondition = optionalConditionNumber,
        mainValue = mainVal,
        optValue = optVal,
        relation = relation,
    }

    if index then
        config.rules[index] = ruleData -- overwrite
    else
        table.insert(config.rules, ruleData) -- create new one
        index = #config.rules
    end

    -- Keep existing enabled flags; clear legacy activeRule pointer
    config.activeRule = nil

    -- Reset display flag on all children
    local children = listPanel.list:getChildren()
    for i = 1, #children do
        children[i].display = false
    end
    
    resetFields()
    invalidateRulesCache()  -- Important: invalidate cache after rule changes
    refreshRules()
    saveConfig()  -- Persist to CharacterDB
end

mainWindow.bossList.onClick = function(widget)
    if bossPanel:isVisible() then
        bossPanel:hide()
        listPanel:show()
        widget:setText('Boss List')
    else
        bossPanel:show()
        listPanel:hide()
        widget:setText('Rule List')

    end
end

-- create boss labels
for i, v in ipairs(config.bosses) do
    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(v)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, v))
        widget:destroy()
        saveConfig()  -- Persist to CharacterDB
    end
end

bossPanel.add.onClick = function()
    local name = bossPanel.name:getText()

    if name:len() == 0 then
        return warn("[Equipped] Please enter boss name!")
    elseif table.find(config.bosses, name:lower(), true) then
        return warn("[Equipper] Boss already added!")
    end

    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(name)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, name))
        widget:destroy()
        saveConfig()  -- Persist to CharacterDB
    end    

    table.insert(config.bosses, name)
    bossPanel.name:setText('')
    saveConfig()  -- Persist to CharacterDB
end

-- `interpreteCondition` removed: condition evaluation now delegated to `EquipperService.evalCondition` with a local fallback `LOCAL_CONDITIONS`.

local function finalCheck(first,relation,second)
    if relation == "-" then
        return first
    elseif relation == "and" then
        return first and second
    elseif relation == "or" then
        return first or second
    end
end

-- ============================================================================
-- SLOT / INVENTORY HELPERS (pure-ish, cached per tick)
-- ============================================================================

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
        hp = hppercent(), mp = manapercent(), monsters = getMonsters(), players = getPlayers(),
        target = target() and target():getName():lower() or nil, inPz = isInPz(), paralyzed = isParalyzed(),
        danger = (TargetBot and TargetBot.Danger and TargetBot.Danger()) or 0,
        cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
        targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
        healbotOn = (storage["healbot"] and storage["healbot"][1] and storage["healbot"][1].enabled) or false,
        bosses = config.bosses or {},
    }
end

local isUnsafeToUnequip = EquipperService and EquipperService.isUnsafeToUnequip or function(ctx)
    if ctx.inPz then return false end
    if ctx.hp <= 35 then return true end
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

-- ============================================================================
-- CONDITIONS (table-driven)
-- ============================================================================

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
    -- Debug: uncomment below to see condition evaluation
    -- info("[EQ Debug] Rule '" .. (rule.name or "?") .. "' condition " .. tostring(rule.mainCondition) .. " value " .. tostring(rule.mainValue) .. " ctx.mp=" .. tostring(ctx.mp) .. " result=" .. tostring(mainOk))
    if rule.relation == "-" then return mainOk end
    local optOk = evalCondition(rule.optionalCondition, rule.optValue, ctx)
    if rule.relation == "and" then return mainOk and optOk end
    if rule.relation == "or" then return mainOk or optOk end
    return mainOk
end

-- ============================================================================
-- ============================================================================
-- ACTION PLANNING (pure decision-making)
-- ============================================================================

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


local function markChild(child)
    if mainWindow:isVisible() then
        local children = listPanel.list:getChildren()
        for i = 1, #children do
            local c = children[i]
            if c ~= child then
                c:setColor('white')
            end
        end
        if child then child:setColor('green') end
    end
end

-- ============================================================================
-- EVENT SUBSCRIPTIONS - Listen for condition changes
-- ============================================================================

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
    
    -- Skip during critical healing
    if HealContext and HealContext.isCritical and HealContext.isCritical() then
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

-- ============================================================================
-- MAIN EQUIPMENT MACRO
-- Single point of equipment checking - runs throttled checks
-- ============================================================================

EquipManager = macro(300, function()
    if not config.enabled then return end

    -- Skip gear swaps during critical healing/danger to avoid conflicts
    if HealContext and HealContext.isCritical and HealContext.isCritical() then
        return
    end

    -- Run the throttled check (respects cooldowns internally)
    throttledEquipCheck()
end)

-- ============================================================================
-- EVENT-DRIVEN EQUIPMENT MANAGEMENT
-- Listen to equipment changes to invalidate cache
-- ============================================================================

if EventBus then
    EventBus.on("equipment:change", function(slotId, slotName, currentId, lastId, item)
        -- Invalidate state on equipment change
        EquipState.needsEquipCheck = true
        EquipState.correctEq = false
        invalidateInventoryCache()
    end, 50)
end

-- End of Equipper module