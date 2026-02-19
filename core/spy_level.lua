-- config

local keyUp = "="
local keyDown = "-"
local keyToggle = "Ctrl+Shift+L"

-- Explicit opt-in for spy level behavior
local spyLevelEnabled = false
if storage then
    if storage.tools and storage.tools.spyLevelEnabled ~= nil then
        spyLevelEnabled = storage.tools.spyLevelEnabled
    elseif storage.spyLevelEnabled ~= nil then
        spyLevelEnabled = storage.spyLevelEnabled
    end
end

local function setSpyLevelEnabled(val)
    spyLevelEnabled = val and true or false
    if storage then
        storage.tools = storage.tools or {}
        storage.tools.spyLevelEnabled = spyLevelEnabled
    end
    print("[SpyLevel] " .. (spyLevelEnabled and "enabled" or "disabled"))
end
setDefaultTab("Tools")

-- script

local lockedLevel = pos().z

onPlayerPositionChange(function(newPos, oldPos)
    if not spyLevelEnabled then return end
    lockedLevel = pos().z
    -- Only call unlockVisibleFloor on actual floor changes to avoid UI freezes
    if not oldPos or newPos.z ~= oldPos.z then
        modules.game_interface.getMapPanel():unlockVisibleFloor()
    end
end)

onKeyPress(function(keys)
    if keys == keyToggle then
        setSpyLevelEnabled(not spyLevelEnabled)
        return
    end
    if not spyLevelEnabled then return end
    if keys == keyDown then
        lockedLevel = lockedLevel + 1
        modules.game_interface.getMapPanel():lockVisibleFloor(lockedLevel)
    elseif keys == keyUp then
        lockedLevel = lockedLevel - 1
        modules.game_interface.getMapPanel():lockVisibleFloor(lockedLevel)
    end
end)