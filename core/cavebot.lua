-- Cavebot by otclient@otclient.ovh
-- visit the documentation on GitHub
-- https://github.com/mCodex/nExBot/blob/main/docs/CAVEBOT.md

local cavebotTab = "Cave"
local targetingTab = storage.extras.joinBot and "Cave" or "Target"

setDefaultTab(cavebotTab)
CaveBot.Extensions = {}

local function safeDofile(path)
	local ok, res = pcall(function() return dofile(path) end)
	if ok then
		return res
	else
		warn("[CaveBot] Failed to load " .. path .. ": " .. tostring(res))
	end
	return res
end

-- Essential UI and core modules (load immediately)
importStyle("/cavebot/cavebot.otui")
importStyle("/cavebot/config.otui")
importStyle("/cavebot/editor.otui")
safeDofile("/cavebot/actions.lua")
safeDofile("/cavebot/config.lua")
safeDofile("/cavebot/example_functions.lua")
safeDofile("/cavebot/editor.lua")
safeDofile("/cavebot/recorder.lua")
safeDofile("/cavebot/tools.lua")
safeDofile("/cavebot/walking.lua")

-- DEBUG: Verify walking module loaded correctly
if CaveBot and CaveBot.resetWalking then
  info("[CaveBot] walking.lua: resetWalking is properly defined")
else
  warn("[CaveBot] walking.lua: ERROR - resetWalking is NOT defined!")
end

safeDofile("/cavebot/minimap.lua")

-- Defer auxiliary modules to reduce startup cost; cavebot.lua must be last (depends on all above)
local deferredModules = {
	"/cavebot/sell_all.lua",
	"/cavebot/depositor.lua",
	"/cavebot/buy_supplies.lua",
	"/cavebot/d_withdraw.lua",
	"/cavebot/supply_check.lua",
	"/cavebot/travel.lua",
	"/cavebot/doors.lua",
	"/cavebot/pos_check.lua",
	"/cavebot/withdraw.lua",
	"/cavebot/inbox_withdraw.lua",
	"/cavebot/lure.lua",
	"/cavebot/bank.lua",
	"/cavebot/clear_tile.lua",
	"/cavebot/tasker.lua",
	"/cavebot/imbuing.lua",
	"/cavebot/stand_lure.lua",
	"/cavebot/cavebot.lua" -- Must remain last (depends on walking.lua, recorder.lua, etc.)
}

local function loadDeferred(idx)
	idx = idx or 1
	if idx > #deferredModules then return end
	setDefaultTab(cavebotTab)
		safeDofile(deferredModules[idx])
	schedule(20, function() loadDeferred(idx + 1) end)
end

loadDeferred()

setDefaultTab(targetingTab)
if storage.extras.joinBot then UI.Label("-- [[ TargetBot ]] --") end
TargetBot = {} -- global namespace
importStyle("/targetbot/looting.otui")
importStyle("/targetbot/target.otui")
importStyle("/targetbot/creature_editor.otui")
importStyle("/targetbot/monster_inspector.otui")

-- Load TargetBot core module first (shared utilities)
dofile("/targetbot/core.lua")

-- Load new optimized modules (SRP extractions from monster_ai.lua)
dofile("/targetbot/monster_tracking.lua")     -- Per-monster data collection with ring buffers
dofile("/targetbot/monster_prediction.lua")   -- Wave/attack prediction logic
dofile("/targetbot/auto_tuner.lua")           -- Monster classification and auto-tuning

-- Load AI and optimization modules (before creature_attack)
dofile("/targetbot/monster_ai.lua")           -- Monster behavior analysis
dofile("/targetbot/movement_coordinator.lua") -- Coordinated movement system

-- Load AttackStateMachine for linear, consistent targeting (before creature.lua)
dofile("/targetbot/attack_state_machine.lua") -- State machine for attack persistence

-- Load TargetBot modules
dofile("/targetbot/creature.lua")

-- Event-driven targeting system (uses EventBus + Creature configs)
dofile("/targetbot/event_targeting.lua")      -- High-performance EventBus targeting

-- Monster inspector UI (visualize learned patterns)
dofile("/targetbot/monster_inspector.lua")
dofile("/targetbot/creature_attack.lua")
dofile("/targetbot/creature_editor.lua")
dofile("/targetbot/creature_priority.lua")
dofile("/targetbot/looting.lua")
dofile("/targetbot/eat_food.lua")  -- Eat food from corpses
dofile("/targetbot/walking.lua")
-- main targetbot file, must be last
dofile("/targetbot/target.lua")
