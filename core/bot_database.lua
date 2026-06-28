local StorageEngine = nExBot.StorageEngine
if not StorageEngine then
  warn("[BotDatabase] StorageEngine not loaded")
  return
end
local engine = StorageEngine.new({
  filename = "BotDatabase.json",
  pathStrategy = "profile",
  debounceMs = 500,
  maxFileSize = 10 * 1024 * 1024,
  defaults = {
    version = 1,
    macros = {
      exchangeMoney = false, autoTradeMsg = false, autoHaste = false,
      autoMount = false, manaTraining = false, eatFood = false,
      antiRs = false, holdTarget = false, exetaLowHp = false,
      exetaIfPlayer = false, depotWithdraw = false, quiverManager = false,
      fishing = false,
    },
    tools = {
      manaTraining = { spell = "exura", minManaPercent = 80 },
      autoTradeMessage = "nExBot is online!",
      fishing = { dropFish = true },
    },
    dropper = { enabled = false, trashItems = {}, useItems = {}, capItems = {} },
    autoEquip = {},
    supplies = { eatFromCorpses = false, sellItems = {} },
    analytics = { showOnStartup = false },
  },
})

BotDB = engine

local _registeredMacros = {}

function BotDB.registerMacro(macroRef, key, onEnable)
  if not macroRef or not storage then return end
  if not storage._macros then storage._macros = {} end
  local macroName = macroRef.name
  if not macroName or macroName == "" then macroName = key end
  if storage._macros[macroName] == nil then storage._macros[macroName] = false end
  local saved = (storage._macros[macroName] == true)
  if macroRef.setOn then
    if saved then macroRef:setOn() else macroRef:setOff() end
  end
  if saved and onEnable then schedule(100, onEnable) end
  _registeredMacros[key] = macroRef
end

function BotDB.getMacro(key) return _registeredMacros[key] end

function BotDB.getMacroState(key)
  local m = _registeredMacros[key]
  if m and m.isOn then return m:isOn() end
  return false
end

function BotDB.setMacroState(key, enabled)
  local m = _registeredMacros[key]
  if not m then return end
  if enabled then if m.setOn then m:setOn() end else if m.setOff then m:setOff() end end
end

local function migrateOldData()
  if not storage then return end
  if not storage._macros then storage._macros = {} end
  local legacy = {
    exchangeMoneyEnabled = "Exchange Money", autoTradeMsgEnabled = "Send message on trade",
    autoHasteEnabled = "Auto Haste", autoMountEnabled = "Auto Mount",
    manaTrainingEnabled = "Mana Training", eatFoodEnabled = "Eat Food",
    fishingEnabled = "Fishing", followPlayerEnabled = "Follow Player",
  }
  for old, name in pairs(legacy) do
    if storage[old] ~= nil and storage._macros[name] == nil then
      storage._macros[name] = (storage[old] == true)
    end
  end
  local macroKeys = {
    macro_exchangeMoney = "Exchange Money", macro_autoTradeMsg = "Send message on trade",
    macro_autoHaste = "Auto Haste", macro_autoMount = "Auto Mount",
    macro_manaTraining = "Mana Training", macro_eatFood = "Eat Food",
    macro_fishing = "Fishing", macro_followPlayer = "Follow Player",
  }
  for old, name in pairs(macroKeys) do
    if storage[old] ~= nil and storage._macros[name] == nil then
      storage._macros[name] = (storage[old] == true)
    end
  end
end

engine.load()
migrateOldData()

nExBot = nExBot or {}
nExBot.BotDB = BotDB
