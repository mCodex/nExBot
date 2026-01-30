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

-- script by kondrah, don't edit below unless you know what you are doing
UI.Label("Auto equip")

-- Load from profile storage
local autoEquip = getProfileSetting("autoEquip") or {}

for i=1,scripts do
  if not autoEquip[i] then
    autoEquip[i] = {on=false, title="Auto Equip", item1=i == 1 and 3052 or 0, item2=i == 1 and 3089 or 0, slot=i == 1 and 9 or 0}
  end
  UI.TwoItemsAndSlotPanel(autoEquip[i], function(widget, newParams)
    autoEquip[i] = newParams
    setProfileSetting("autoEquip", autoEquip)
  end)
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