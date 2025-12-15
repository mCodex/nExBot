-- Heal safety guard: pauses combat/automation while healing is critical
-- Uses HealContext flags to gate TargetBot, CaveBot, and AttackBot
-- Includes small hysteresis to avoid rapid toggling.

local HealContext = dofile("/core/heal_context.lua")

setDefaultTab("HP")
local ui = setupUI([[ 
Panel
  height: 42
  margin-top: 2

  Label
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text: Heal thresholds
    color: green

  Label
    id: hpLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: HP <=

  SpinBox
    id: hp
    anchors.top: prev.top
    anchors.left: prev.right
    width: 45
    minimum: 1
    maximum: 100

  Label
    id: dangerLabel
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 6
    text: Danger >=

  SpinBox
    id: danger
    anchors.top: prev.top
    anchors.left: prev.right
    width: 55
    minimum: 1
    maximum: 200

  Button
    id: save
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 4
    text: Save thresholds
]])

ui.hp:setValue(storage.healThresholds.hpCritical)
ui.danger:setValue(storage.healThresholds.dangerCritical)

ui.save.onClick = function()
  storage.healThresholds.hpCritical = ui.hp:getValue()
  storage.healThresholds.dangerCritical = ui.danger:getValue()
  HealContext.setThresholds(storage.healThresholds)
end

local restoreState = {
  target = false,
  cave = false,
  attack = false,
}

local function setOffSafe(bot)
  if bot and bot.isOn and bot.isOn() and bot.setOff then
    bot.setOff()
    return true
  end
  return false
end

local function setOnSafe(bot)
  if bot and bot.setOn then
    bot.setOn()
    return true
  end
  return false
end

-- Macro interval aligns with EquipManager (250ms) but remains responsive
macro(200, "Heal Safety Guard", function()
  local snap = HealContext.get()
  local isCritical = HealContext.isCritical()
  storage.healCritical = isCritical

  if isCritical then
    -- Pause bots while we stabilize
    restoreState.target = restoreState.target or setOffSafe(TargetBot)
    restoreState.cave = restoreState.cave or setOffSafe(CaveBot)
    restoreState.attack = restoreState.attack or setOffSafe(AttackBot)
    return
  end

  -- Recover with hysteresis to prevent flapping
  local safeHp = snap.hp > (HealContext.thresholds.hpCritical + 5)
  local safeDanger = snap.danger < (HealContext.thresholds.dangerCritical - 10)

  if safeHp and safeDanger then
    if restoreState.target then setOnSafe(TargetBot) end
    if restoreState.cave then setOnSafe(CaveBot) end
    if restoreState.attack then setOnSafe(AttackBot) end
    restoreState.target = false
    restoreState.cave = false
    restoreState.attack = false
  end
end)
