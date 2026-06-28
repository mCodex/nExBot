local StorageEngine = nExBot.StorageEngine
if not StorageEngine then
  warn("[CharacterDB] StorageEngine not loaded")
  return
end
local engine = StorageEngine.new({
  filename = "CharacterDB.json",
  pathStrategy = "character",
  debounceMs = 500,
  maxFileSize = 5 * 1024 * 1024,
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
      fishing = { dropFish = true },
      followPlayer = { enabled = false, playerName = "" },
    },
    equipper = { enabled = false, rules = {}, bosses = {}, activeRule = nil },
    containers = {
      purse = true, autoMinimize = true, autoOpenOnLogin = false,
      sortEnabled = false, forceOpen = false, renameEnabled = false,
      lootBag = false, containerList = {}, windowHeight = 200,
    },
  },
})

CharacterDB = engine

if g_game.getLocalPlayer() then engine.load() end

nExBot = nExBot or {}
nExBot.CharacterDB = CharacterDB
