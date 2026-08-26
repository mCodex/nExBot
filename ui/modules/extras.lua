local Components = nExBot.UI["ui.components.components"]

local ExtrasPage = {}

-- Declarative page model: each row mirrors an option the retired ExtrasWindow
-- rendered. Values are read live from nExBot.Extras and written back through
-- setSetting, so the engine handlers pick changes up immediately.
local SECTIONS = {
  {
    id = "extrasItems", title = "Items",
    rows = {
      { id = "rope", type = "item", label = "Rope Item", default = 9596, tooltip = "Default rope item used in various bot scripts." },
      { id = "shovel", type = "item", label = "Shovel Item", default = 9596, tooltip = "Default shovel item used in various bot scripts." },
      { id = "machete", type = "item", label = "Machete Item", default = 9596, tooltip = "Default machete item used in various bot scripts." },
      { id = "scythe", type = "item", label = "Scythe Item", default = 9596, tooltip = "Default scythe item used in various bot scripts." },
    },
  },
  {
    id = "extrasCaveBot", title = "CaveBot",
    rows = {
      { id = "pathfinding", type = "toggle", label = "CaveBot Pathfinding", tooltip = "Cavebot will automatically search for first reachable waypoint after missing 10 goto's." },
      { id = "talkDelay", type = "number", label = "Global NPC Talk Delay", default = 1000, tooltip = "Breaks between each talk action in cavebot (time in milliseconds)." },
      { id = "looting", type = "number", label = "Max Loot Distance", default = 40, tooltip = "Every loot corpse further than set distance (in sqm) will be ignored and forgotten." },
      { id = "lootDelay", type = "number", label = "Loot Delay", default = 200, tooltip = "Wait time for loot container to open. Lower value means faster looting. Increase it if the container locks while opening/closing." },
      { id = "huntRoutes", type = "number", label = "Hunting Rounds Limit", default = 50, tooltip = "Round limit for supply check — above it the next supply check returns to city." },
      { id = "killUnder", type = "number", label = "Kill monsters below", default = 1, tooltip = "Force TargetBot to kill added creatures below this health % — ignores other TargetBot settings." },
      { id = "gotoMaxDistance", type = "number", label = "Max GoTo Distance", default = 30, tooltip = "Maximum distance to next goto waypoint the bot will try to reach." },
      { id = "lootLast", type = "toggle", label = "Start loot from last corpse", tooltip = "Looting sequence will be reverted and bot will start looting newest bodies." },
      { id = "joinBot", type = "toggle", label = "Join TargetBot and CaveBot", tooltip = "Cave and Target tabs will be joined into one." },
      { id = "reachable", type = "toggle", label = "Target only pathable mobs", tooltip = "Ignore monsters that can't be reached." },
      { id = "stake", type = "toggle", label = "Skin Monsters", tooltip = "Automatically skin & stake corpses when cavebot is enabled." },
      { id = "suppliesControl", type = "toggle", label = "TargetBot off if low supply", tooltip = "Turn off TargetBot if either supply amount is below 50% of minimum." },
      { id = "nextBackpack", type = "toggle", label = "Open Next Loot Container", tooltip = "Auto open next loot container if full - has to have the same ID." },
    },
  },
  {
    id = "extrasMisc", title = "Miscellaneous",
    rows = {
      { id = "title", type = "toggle", label = "Custom Window Title", tooltip = "Personalize OTCv8 window name according to character specific." },
      { id = "separatePm", type = "toggle", label = "Open PM's in new Window", tooltip = "PM's will be automatically opened in new tab after receiving one." },
      { id = "useAll", type = "text", label = "Use All Hotkey", default = "space", tooltip = "Set hotkey for universal actions - rope, shovel, scythe, use, open doors" },
      { id = "timers", type = "toggle", label = "MW & WG Timers", tooltip = "Show times for Magic Walls and Wild Growths." },
      { id = "antiKick", type = "toggle", label = "Anti - Kick", tooltip = "Turn every 10 minutes to prevent kick." },
      { id = "oberon", type = "toggle", label = "Auto Reply Oberon", tooltip = "Auto reply to Grand Master Oberon talk minigame." },
      { id = "autoOpenDoors", type = "toggle", label = "Auto Open Doors", tooltip = "Open doors when trying to step on them." },
      { id = "bless", type = "toggle", label = "Buy bless at login", tooltip = "Say !bless at login." },
      { id = "reUse", type = "toggle", label = "Keep Crosshair", tooltip = "Keep crosshair after using with item" },
      { id = "holdMwall", type = "toggle", label = "Hold MW/WG", tooltip = "Mark tiles with below hotkeys to automatically use Magic Wall or Wild Growth." },
      { id = "holdMwHot", type = "text", label = "Magic Wall Hotkey", default = "F5" },
      { id = "holdWgHot", type = "text", label = "Wild Growth Hotkey", default = "F6" },
      { id = "checkPlayer", type = "toggle", label = "Check Players", tooltip = "Auto look on players and mark level and vocation on character model." },
      { id = "highlightTarget", type = "toggle", label = "Highlight Current Target", tooltip = "Additionally highlight current target with red glow." },
    },
  },
}

local function renderRow(content, extras, row)
  local value = extras.getSetting(row.id)
  if value == nil then value = row.default end
  if row.type == "toggle" then
    Components.toggleRow(content, {
      id = "extras_" .. row.id, label = row.label,
      value = value == true, tooltip = row.tooltip,
      onChange = function(v) extras.setSetting(row.id, v) end,
    })
  else
    Components.inputRow(content, {
      id = "extras_" .. row.id, label = row.label,
      value = tostring(value), tooltip = row.tooltip,
      onChange = function(text)
        if row.type == "number" or row.type == "item" then
          local v = tonumber(text)
          if v then extras.setSetting(row.id, v) end
        else
          extras.setSetting(row.id, text)
        end
      end,
    })
  end
end

function ExtrasPage.render(shell, content)
  local extras = nExBot.Extras
  if not extras or not extras.getSetting then
    Components.errorState(content, { message = "Extras did not load. Check the startup log." })
    return
  end

  Components.pageHeader(content, {
    id = "extrasHeader", textId = "extrasHeaderText",
    title = "Extras", subtitle = "Global tweaks and automation options.",
  })
  for _, section in ipairs(SECTIONS) do
    Components.sectionHeader(content, { id = section.id, title = section.title })
    for _, row in ipairs(section.rows) do
      renderRow(content, extras, row)
    end
  end
end

nExBot.UI.ModuleRegistry.register({
  id = "extras", label = "Extras", order = 83,
  render = ExtrasPage.render,
})
nExBot.UI.ExtrasPage = ExtrasPage
nExBot.UI["ui.modules.extras"] = ExtrasPage

return ExtrasPage