std = "luajit"
max_line_length = 120

-- OTClient runtime globals (read-only)
read_globals = {
  -- OTClient core
  "g_game", "g_map", "g_ui", "g_things", "g_clock", "g_resources", "g_platform", "g_http", "HTTP",
  "modules", "macro", "schedule", "dofile", "periodic", "g_items",
  "now", "autoWalk",

  -- Player accessors
  "pos", "target", "player", "mana", "hppercent", "manapercent",

  -- State checks
  "isInPz", "isParalyzed", "isBurning", "isPoisoned",

  -- Actions
  "cast", "say", "turn", "follow", "useWith",

  -- Item/Path/Creature queries
  "findItem", "findPath", "getSpectators", "getMonsters", "getPlayers",
  "distanceFromPlayer", "burstDamageValue",

  -- Native callback registration (all optional, may not exist)
  "onCreatureAppear", "onCreatureDisappear", "onCreatureHealthPercentChange",
  "onPlayerPositionChange", "onManaChange", "onHealthChange",
  "onPlayerZChange", "onPlayerWalkError",
  "onContainerOpen", "onContainerClose", "onContainerUpdateItem",
  "onAttackingCreatureChange", "onTextMessage", "onTalk",
  "onAddThing", "onRemoveThing", "onWalk", "onTurn", "onMissle",
  "onAnimatedText", "onStaticText", "onUse", "onUseWith",
  "onAddItem", "onRemoveItem", "onInventoryChange", "onStatesChange",
  "onModalDialog", "onChannelList", "onOpenChannel", "onCloseChannel",
  "onSpellCooldown", "onGroupSpellCooldown",
  "onPlayerHealthChange", "onPlayerManaChange",

  -- UI
  "setDefaultTab", "setupUI", "UI",

  -- Lua stdlib shims
  "TrimArray", "table.removevalue", "table.find", "string.split",
  "ThingCategoryItem",
}

-- Project globals (will shrink as we extract modules)
globals = {
  "nExBot", "EventBus", "UnifiedTick", "UnifiedStorage",
  "BotCore", "HealBot", "HealEngine", "HealContext", "AttackBot",
  "TargetBot", "TargetCore", "PriorityEngine", "CombatConstants",
  "CaveBot", "SafeCall", "ClientService", "SafeCreature",
  "MonsterAI", "AttackStateMachine", "MovementCoordinator",
  "HealBotConfig", "AttackBotConfig",
  "ZChangeGuard", "KillTracker",
  "AttackData", "AttackAnalytics", "AttackConfig", "CombatExecutor",
  "HealConfig", "SpellResolver", "HealAnalytics",
  "storage", "info", "warn",
}

-- Files to exclude from linting
exclude_files = {
  "cavebot_configs/**",
  "targetbot_configs/**",
  "nExBot_configs/**",
  "private/**",
  "tests/**",
}
