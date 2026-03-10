-- config
setDefaultTab("HP")
local scripts = 2 -- if you want more auto equip panels you can change 2 to higher value

-- Non-blocking cooldown state
local lastEquipTime = 0
local EQUIP_COOLDOWN = 1000

-- Profile storage helpers
local function getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

local function setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

-- script by kondrah, refactored with NxSwitch UI
setupUI([[
Panel
  height: 16

  NxHeading
    id: heading
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    !text: tr('Auto equip')
]])

-- Load from profile storage
local autoEquip = getProfileSetting("autoEquip") or {}

-- Slot name lookup for display
local SLOT_NAMES = {
  [1] = "Head", [2] = "Necklace", [3] = "Backpack", [4] = "Armor",
  [5] = "Right Hand", [6] = "Left Hand", [7] = "Legs", [8] = "Feet",
  [9] = "Ring", [10] = "Ammo"
}

for i = 1, scripts do
  if not autoEquip[i] then
    autoEquip[i] = {on = false, title = "Auto Equip", item1 = i == 1 and 3052 or 0, item2 = i == 1 and 3089 or 0, slot = i == 1 and 9 or 0}
  end

  local cfg = autoEquip[i]

  local panel = setupUI([[
NxPanel
  height: 64
  margin-top: 4
  padding: 4

  NxSwitch
    id: toggle
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    !text: tr('Auto Equip ]] .. i .. [[')

  NxItem
    id: item1
    anchors.top: toggle.bottom
    anchors.left: parent.left
    margin-top: 4
    size: 34 34

  NxItem
    id: item2
    anchors.top: toggle.bottom
    anchors.left: item1.right
    margin-top: 4
    margin-left: 4
    size: 34 34

  NxComboBox
    id: slotCombo
    anchors.verticalCenter: item1.verticalCenter
    anchors.left: item2.right
    anchors.right: parent.right
    margin-left: 6
]])

  -- Initialize widget states from saved config
  panel.toggle:setOn(cfg.on == true)
  if cfg.item1 and cfg.item1 > 0 then panel.item1:setItemId(cfg.item1) end
  if cfg.item2 and cfg.item2 > 0 then panel.item2:setItemId(cfg.item2) end

  -- Populate slot combobox with names
  for s = 1, 10 do
    panel.slotCombo:addOption(SLOT_NAMES[s], s)
  end
  panel.slotCombo:setCurrentIndex(cfg.slot or 1)

  -- Save helper
  local function saveEquip()
    setProfileSetting("autoEquip", autoEquip)
  end

  -- NxSwitch toggle
  panel.toggle.onClick = function(widget)
    cfg.on = not cfg.on
    widget:setOn(cfg.on)
    saveEquip()
  end

  -- Item change callbacks
  panel.item1.onItemChange = function(widget)
    cfg.item1 = widget:getItemId()
    saveEquip()
  end

  panel.item2.onItemChange = function(widget)
    cfg.item2 = widget:getItemId()
    saveEquip()
  end

  -- Slot combobox change
  panel.slotCombo.onOptionChange = function(widget, text, data)
    cfg.slot = data
    saveEquip()
  end
end

-- Auto equip handler function (shared by UnifiedTick and fallback macro)
local function autoEquipHandler()
  -- Non-blocking cooldown check
  if (now - lastEquipTime) < EQUIP_COOLDOWN then return end
  
  local containers = g_game.getContainers()
  for index, equipConfig in ipairs(autoEquip) do
    if equipConfig.on then
      local slotItem = getSlot(equipConfig.slot)
      if not slotItem or (slotItem:getId() ~= equipConfig.item1 and slotItem:getId() ~= equipConfig.item2) then
        for _, container in pairs(containers) do
          for __, item in ipairs(container:getItems()) do
            if item:getId() == equipConfig.item1 or item:getId() == equipConfig.item2 then
              g_game.move(item, {x=65535, y=equipConfig.slot, z=0}, item:getCount())
              lastEquipTime = now -- Non-blocking cooldown
              return
            end
          end
        end
      end
    end
  end
end

-- Use UnifiedTick if available, fallback to standalone macro
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("auto_equip", {
    interval = 250,
    priority = UnifiedTick.Priority.LOW,
    handler = autoEquipHandler,
    group = "equipment"
  })
else
  macro(250, autoEquipHandler)
end