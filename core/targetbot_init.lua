-- Cavebot by otclient@otclient.ovh
-- visit the documentation on GitHub
-- https://www.nexbot.cc/docs/cavebot

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

safeDofile("/cavebot/minimap.lua")

-- Defer auxiliary cavebot + targetbot modules to reduce perceived startup cost.
-- cavebot.lua must come last within cavebot/ (depends on walking, recorder, etc.).
-- target.lua must come last within targetbot/ (depends on all subsystems).
local deferredModules = {
	-- Cavebot auxiliaries
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
	"/cavebot/cavebot.lua", -- Last cavebot file (depends on walking.lua, recorder.lua)

	-- TargetBot (deferred to keep startup snappy; bot is offline at boot so the
	-- ~1s asynchronous load window is invisible to the user).
	-- Subsystems first, orchestrator + target.lua last.
	"__TARGETBOT_HEADER__",
	"/targetbot/core.lua",
	"/targetbot/monster_ai_core.lua",
	"/targetbot/monster_patterns.lua",
	"/targetbot/monster_tracking.lua",
	"/targetbot/monster_prediction.lua",
	"/targetbot/monster_combat_feedback.lua",
	"/targetbot/monster_spell_tracker.lua",
	"/targetbot/auto_tuner.lua",
	"/targetbot/monster_scenario.lua",
	"/targetbot/monster_reachability.lua",
	"/targetbot/monster_tbi.lua",
	"/targetbot/monster_ai.lua",
	"/targetbot/movement_coordinator.lua",
	"/targetbot/combat_constants.lua",
	"/targetbot/attack_state_machine.lua",
	"/targetbot/creature.lua",
	"/targetbot/event_targeting.lua",
	"/targetbot/monster_inspector.lua",
	"/targetbot/creature_attack.lua",
	"/targetbot/priority_engine.lua",
	"/targetbot/creature_editor.lua",
	"/targetbot/creature_priority.lua",
	"/targetbot/looting.lua",
	"/targetbot/eat_food.lua",
	"/targetbot/walking.lua",
	"/targetbot/target.lua", -- Main TargetBot file, must be last
}

-- TargetBot UI groundwork that must exist before any targetbot file loads
local function initTargetBot()
	setDefaultTab(targetingTab)
	if storage.extras.joinBot then UI.Label("-- [[ TargetBot ]] --") end
	TargetBot = TargetBot or {} -- global namespace
	importStyle("/targetbot/looting.otui")
	importStyle("/targetbot/target.otui")
	importStyle("/targetbot/creature_editor.otui")
	importStyle("/targetbot/monster_inspector.otui")
end

local _inTargetBotSection = false
local function loadDeferred(idx)
	idx = idx or 1
	if idx > #deferredModules then
		nExBot = nExBot or {}
		nExBot.bootReady = true
		return
	end
	local entry = deferredModules[idx]
	if entry == "__TARGETBOT_HEADER__" then
		initTargetBot()
		_inTargetBotSection = true
	else
		-- Route UI built during this dofile to the correct tab.
		setDefaultTab(_inTargetBotSection and targetingTab or cavebotTab)
		safeDofile(entry)
	end
	schedule(20, function() loadDeferred(idx + 1) end)
end

loadDeferred()
