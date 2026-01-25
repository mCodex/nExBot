--[[
  nExBot ACL - Interface Definitions
  
  Defines the standard interfaces that all client adapters must implement.
  This ensures consistency across different OTClient implementations.
  
  Principles:
  - Interface Segregation: Small, focused interfaces
  - Dependency Inversion: Depend on abstractions, not implementations
]]

local Interfaces = {}

--------------------------------------------------------------------------------
-- GAME INTERFACE
-- Core game operations (attack, follow, move items, etc.)
--------------------------------------------------------------------------------

Interfaces.IGame = {
  -- Player Actions
  "attack",           -- (creature) -> void
  "cancelAttack",     -- () -> void
  "follow",           -- (creature) -> void
  "cancelFollow",     -- () -> void
  "cancelAttackAndFollow", -- () -> void
  
  -- Movement
  "walk",             -- (direction) -> bool
  "autoWalk",         -- (destination, options) -> bool
  "turn",             -- (direction) -> void
  "stop",             -- () -> void
  
  -- Items
  "move",             -- (item, toPos, count) -> void
  "use",              -- (item) -> void
  "useWith",          -- (item, target) -> void
  "useInventoryItem", -- (itemId) -> void
  "look",             -- (thing) -> void
  "rotate",           -- (thing) -> void
  
  -- Communication
  "talk",             -- (message) -> void
  "talkChannel",      -- (mode, channelId, message) -> void
  "talkPrivate",      -- (mode, receiver, message) -> void
  "requestChannels",  -- () -> void
  "joinChannel",      -- (channelId) -> void
  "leaveChannel",     -- (channelId) -> void
  
  -- Containers
  "open",             -- (item, previousContainer?) -> int
  "openParent",       -- (container) -> void
  "close",            -- (container) -> void
  "refreshContainer", -- (container) -> void
  
  -- State Queries
  "isOnline",         -- () -> bool
  "isDead",           -- () -> bool
  "isAttacking",      -- () -> bool
  "isFollowing",      -- () -> bool
  "getLocalPlayer",   -- () -> LocalPlayer
  "getAttackingCreature", -- () -> Creature | nil
  "getFollowingCreature", -- () -> Creature | nil
  "getContainer",     -- (id) -> Container | nil
  "getContainers",    -- () -> table<int, Container>
  
  -- Protocol
  "getClientVersion", -- () -> int
  "getProtocolVersion", -- () -> int
  "getFeature",       -- (feature) -> bool
  "enableFeature",    -- (feature) -> void
  "disableFeature",   -- (feature) -> void
  
  -- Combat Settings
  "getChaseMode",     -- () -> int
  "getFightMode",     -- () -> int
  "setChaseMode",     -- (mode) -> void
  "setFightMode",     -- (mode) -> void
  "isSafeFight",      -- () -> bool
  "setSafeFight",     -- (safe) -> void
  
  -- Trading
  "buyItem",          -- (item, count, ignoreEquipped, ignoreCap) -> void
  "sellItem",         -- (item, count) -> void
  "closeNpcTrade",    -- () -> void
  
  -- Other
  "getUnjustifiedPoints", -- () -> table
  "getPing",          -- () -> int
  "equipItem",        -- (item) -> void
  "requestOutfit",    -- () -> void
  "changeOutfit",     -- (outfit) -> void
}

--------------------------------------------------------------------------------
-- MAP INTERFACE
-- Map and tile operations
--------------------------------------------------------------------------------

Interfaces.IMap = {
  "getTile",              -- (pos) -> Tile | nil
  "getSpectators",        -- (pos, multifloor?) -> table<Creature>
  "isSightClear",         -- (fromPos, toPos, floorCheck) -> bool
  "isLookPossible",       -- (pos) -> bool
  "cleanDynamicThings",   -- () -> void
  "findPath",             -- (startPos, goalPos, options) -> table<Position>
}

--------------------------------------------------------------------------------
-- PLAYER INTERFACE
-- Local player specific operations
--------------------------------------------------------------------------------

Interfaces.IPlayer = {
  -- Stats
  "getHealth",        -- () -> int
  "getMaxHealth",     -- () -> int
  "getMana",          -- () -> int
  "getMaxMana",       -- () -> int
  "getLevel",         -- () -> int
  "getExperience",    -- () -> number
  "getMagicLevel",    -- () -> int
  "getSoul",          -- () -> int
  "getStamina",       -- () -> int
  "getCapacity",      -- () -> number
  "getTotalCapacity", -- () -> number
  "getVocation",      -- () -> int
  "getBlessings",     -- () -> int
  
  -- Position & Movement
  "getPosition",      -- () -> Position
  "getDirection",     -- () -> int
  "isWalking",        -- () -> bool
  "getSpeed",         -- () -> int
  "getStates",        -- () -> int
  
  -- Skills
  "getSkillLevel",    -- (skillId) -> int
  "getSkillBaseLevel", -- (skillId) -> int
  "getSkillPercent",  -- (skillId) -> int
  
  -- Equipment
  "getInventoryItem", -- (slot) -> Item | nil
  "getName",          -- () -> string
  "getId",            -- () -> int
  
  -- Combat
  "getSkull",         -- () -> int
  "isPartyMember",    -- () -> bool
  "hasPartyBuff",     -- () -> bool
}

--------------------------------------------------------------------------------
-- CREATURE INTERFACE
-- Creature operations
--------------------------------------------------------------------------------

Interfaces.ICreature = {
  "getId",            -- () -> int
  "getName",          -- () -> string
  "getHealthPercent", -- () -> int
  "getPosition",      -- () -> Position
  "getDirection",     -- () -> int
  "getSpeed",         -- () -> int
  "getOutfit",        -- () -> Outfit
  "getSkull",         -- () -> int
  "getEmblem",        -- () -> int
  
  -- Type checks
  "isPlayer",         -- () -> bool
  "isMonster",        -- () -> bool
  "isNpc",            -- () -> bool
  "isLocalPlayer",    -- () -> bool
  "isPartyMember",    -- () -> bool
  "isWalking",        -- () -> bool
  
  -- Custom text
  "setText",          -- (text) -> void
  "getText",          -- () -> string
  "clearText",        -- () -> void
}

--------------------------------------------------------------------------------
-- ITEM INTERFACE
-- Item operations
--------------------------------------------------------------------------------

Interfaces.IItem = {
  "getId",            -- () -> int
  "getCount",         -- () -> int
  "getSubType",       -- () -> int
  "getPosition",      -- () -> Position
  "getContainerId",   -- () -> int | nil
  "isContainer",      -- () -> bool
  "isStackable",      -- () -> bool
  "isFluidContainer", -- () -> bool
  "isUsable",         -- () -> bool
  "isMultiUse",       -- () -> bool
}

--------------------------------------------------------------------------------
-- CONTAINER INTERFACE
-- Container operations
--------------------------------------------------------------------------------

Interfaces.IContainer = {
  "getId",            -- () -> int
  "getItems",         -- () -> table<Item>
  "getItem",          -- (slot) -> Item | nil
  "getItemsCount",    -- () -> int
  "getCapacity",      -- () -> int
  "getName",          -- () -> string
  "getContainerItem", -- () -> Item
  "getSlotPosition",  -- (slot) -> Position
  "isOpen",           -- () -> bool
}

--------------------------------------------------------------------------------
-- TILE INTERFACE
-- Tile operations
--------------------------------------------------------------------------------

Interfaces.ITile = {
  "getPosition",      -- () -> Position
  "getThings",        -- () -> table<Thing>
  "getItems",         -- () -> table<Item>
  "getCreatures",     -- () -> table<Creature>
  "getTopThing",      -- () -> Thing | nil
  "getTopUseThing",   -- () -> Thing | nil
  "getTopCreature",   -- () -> Creature | nil
  "getTopMoveThing",  -- () -> Thing | nil
  "getGround",        -- () -> Item | nil
  
  -- Properties
  "isWalkable",       -- () -> bool
  "isFullGround",     -- () -> bool
  "isBlocking",       -- () -> bool
  "hasCreature",      -- () -> bool
  "isClickable",      -- () -> bool
}

--------------------------------------------------------------------------------
-- CALLBACK INTERFACE
-- Event callbacks that adapters must support
--------------------------------------------------------------------------------

Interfaces.ICallbacks = {
  -- Game events
  "onTalk",
  "onTextMessage",
  "onLoginAdvice",
  
  -- Creature events
  "onCreatureAppear",
  "onCreatureDisappear",
  "onCreaturePositionChange",
  "onCreatureHealthPercentChange",
  "onTurn",
  "onWalk",
  
  -- Player events
  "onPlayerPositionChange",
  "onManaChange",
  "onStatesChange",
  "onInventoryChange",
  
  -- Tile events
  "onAddThing",
  "onRemoveThing",
  
  -- Container events
  "onContainerOpen",
  "onContainerClose",
  "onContainerUpdateItem",
  "onAddItem",
  "onRemoveItem",
  
  -- Combat events
  "onAttackingCreatureChange",
  
  -- UI events
  "onUse",
  "onUseWith",
  "onKeyDown",
  "onKeyUp",
  "onKeyPress",
  
  -- Channel events
  "onChannelList",
  "onOpenChannel",
  "onCloseChannel",
  "onChannelEvent",
  
  -- Spell events
  "onSpellCooldown",
  "onGroupSpellCooldown",
  
  -- Other events
  "onModalDialog",
  "onImbuementWindow",
  "onMissle",
  "onAnimatedText",
  "onStaticText",
  "onGameEditText",
}

--------------------------------------------------------------------------------
-- UI INTERFACE
-- UI-related operations
--------------------------------------------------------------------------------

Interfaces.IUI = {
  "importStyle",      -- (path) -> void
  "createWidget",     -- (type, parent?) -> Widget
  "getRootWidget",    -- () -> Widget
  "loadUI",           -- (path, parent?) -> Widget
}

--------------------------------------------------------------------------------
-- MODULES INTERFACE
-- Module access
--------------------------------------------------------------------------------

Interfaces.IModules = {
  "getGameInterface", -- () -> Module
  "getConsole",       -- () -> Module
  "getCooldown",      -- () -> Module
  "getBot",           -- () -> Module
  "getTerminal",      -- () -> Module
}

--------------------------------------------------------------------------------
-- VALIDATION
-- Validates that an adapter implements required interfaces
--------------------------------------------------------------------------------

function Interfaces.validate(adapter, interfaceName)
  local interface = Interfaces[interfaceName]
  if not interface then
    return false, "Unknown interface: " .. interfaceName
  end
  
  local missing = {}
  for _, method in ipairs(interface) do
    if not adapter[method] or type(adapter[method]) ~= "function" then
      table.insert(missing, method)
    end
  end
  
  if #missing > 0 then
    return false, "Missing methods: " .. table.concat(missing, ", ")
  end
  
  return true
end

return Interfaces
