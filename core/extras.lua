-- securing storage namespace
local zChanging = nExBot.zChanging or function() return false end
local panelName = "extras"
if not storage[panelName] then
  storage[panelName] = {}
end
local settings = storage[panelName]

-- basic elements
-- The standalone window (core/extras.otui) was retired in favor of the shell
-- page ui/modules/extras.lua. Options are now initialized here so the engine
-- keeps the exact defaults the old window applied, then edited through the
-- nExBot.Extras getSetting/setSetting API.
local DEFAULTS = {
  rope = 9596, shovel = 9596, machete = 9596, scythe = 9596,
  pathfinding = true, talkDelay = 1000, looting = 40, lootDelay = 200,
  huntRoutes = 50, killUnder = 1, gotoMaxDistance = 30, lootLast = true,
  joinBot = false, reachable = false, title = true, separatePm = false,
  useAll = "space", timers = true, antiKick = true, stake = false,
  oberon = true, autoOpenDoors = true, bless = true, reUse = false,
  suppliesControl = false, holdMwall = true, holdMwHot = "F5",
  holdWgHot = "F6", checkPlayer = true, nextBackpack = true,
  highlightTarget = true,
}
for id, default in pairs(DEFAULTS) do
  if settings[id] == nil then settings[id] = default end
end

-- Safe no-op kept for legacy callers (actions.lua open_extras): routes to the
-- shell page instead of opening a standalone window.
local function showExtrasWindow()
  local Shell = nExBot and nExBot.UI and nExBot.UI.Shell
  if Shell and Shell.select then
    pcall(Shell.select, "extras")
  end
end

local function openDocumentation()
  g_platform.openUrl("https://nexbot.cc/docs")
end

nExBot.Extras = {
  getSettings = function() return settings end,
  getSetting = function(id) return settings[id] end,
  setSetting = function(id, value) settings[id] = value end,
  showWindow = showExtrasWindow,
  openDocumentation = openDocumentation,
}

---- options are declared above; the feature handlers below read settings live:
if true then
  local vocText = ""
  if Vocations and Vocations.getShortName then
    local short = Vocations.getShortName(voc())
    if short ~= "" then
      vocText = "- " .. short
    end
  end

  -- Window title handler function
  local function windowTitleHandler()
    if settings._titleDisabled then return end
    local ok, err
    if settings.title then
      if hppercent() > 0 then
          ok, err = pcall(g_window.setTitle, "Tibia - " .. name() .. " - " .. lvl() .. "lvl " .. vocText)
      else
          ok, err = pcall(g_window.setTitle, "Tibia - " .. name() .. " - DEAD")
      end
    else
      ok, err = pcall(g_window.setTitle, "Tibia - " .. name())
    end
    if not ok and err then
      warn("[Extras] setTitle failed: " .. tostring(err))
      settings.title = false

      settings._titleDisabled = true
    end
  end

  -- Use UnifiedTick if available, fallback to standalone macro
  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("window_title", {
      interval = 5000,
      priority = UnifiedTick.Priority.IDLE,
      handler = windowTitleHandler,
      group = "ui"
    })
  else
    macro(5000, windowTitleHandler)
  end
end

if true then
  onTalk(function(name, level, mode, text, channelId, pos)
    if mode == 4 and settings.separatePm then
        local g_console = modules.game_console
        local privateTab = g_console.getTab(name)
        if privateTab == nil then
            privateTab = g_console.addTab(name, true)
            g_console.addPrivateText(g_console.applyMessagePrefixies(name, level, text), g_console.SpeakTypesSettings['private'], name, false, name)
        end
        return
    end
  end)
end

if true then
  local useId = { 34847, 1764, 21051, 30823, 6264, 5282, 20453, 20454, 20474, 11708, 11705, 
                  6257, 6256, 2772, 27260, 2773, 1632, 1633, 1948, 435, 6252, 6253, 5007, 4911, 
                  1629, 1630, 5108, 5107, 5281, 1968, 435, 1948, 5542, 31116, 31120, 30742, 31115, 
                  31118, 20474, 5737, 5736, 5734, 5733, 31202, 31228, 31199, 31200, 33262, 30824, 
                  5125, 5126, 5116, 5117, 8257, 8258, 8255, 8256, 5120, 30777, 30776, 23873, 23877,
                  5736, 6264, 31262, 31130, 31129, 6250, 6249, 5122, 30049, 7131, 7132, 7727 }
  local shovelId = { 606, 593, 867, 608 }
  local ropeId = { 17238, 12202, 12935, 386, 421, 21966, 14238 }
  local macheteId = { 2130, 3696 }
  local scytheId = { 3653 }

  -- script
  if settings.useAll and settings.useAll:len() > 0 then
    hotkey(settings.useAll, function()
        local wsadWalking = modules and modules.game_walking and modules.game_walking.wsadWalking
        if not wsadWalking then return end
        -- Only check adjacent tiles (distance < 2) instead of full floor scan
        local playerPos = player:getPosition()
        local nearTiles = getNearTiles(playerPos)
        -- Also check tile under player
        local playerTile = g_map.getTile(playerPos)
        if playerTile then
          for _, item in pairs(playerTile:getItems()) do
            if table.find(useId, item:getId()) then return use(item)
            elseif table.find(shovelId, item:getId()) then return SafeCall.useWith(settings.shovel, item)
            elseif table.find(ropeId, item:getId()) then return SafeCall.useWith(settings.rope, item)
            elseif table.find(macheteId, item:getId()) then return SafeCall.useWith(settings.machete, item)
            elseif table.find(scytheId, item:getId()) then return SafeCall.useWith(settings.scythe, item)
            end
          end
        end
        for _, tile in pairs(nearTiles) do
            for _, item in pairs(tile:getItems()) do
                if table.find(useId, item:getId()) then return use(item)
                elseif table.find(shovelId, item:getId()) then return SafeCall.useWith(settings.shovel, item)
                elseif table.find(ropeId, item:getId()) then return SafeCall.useWith(settings.rope, item)
                elseif table.find(macheteId, item:getId()) then return SafeCall.useWith(settings.machete, item)
                elseif table.find(scytheId, item:getId()) then return SafeCall.useWith(settings.scythe, item)
                end
            end
        end
    end)
  end
end

if true then
  local activeTimers = {}

  -- Consolidated: uses EventBus "tile:add"/"tile:remove" instead of direct
  -- onAddThing/onRemoveThing native hooks.  event_bus.lua already filters to
  -- isItem() and applies z-change + tile-burst throttling before emitting.
  EventBus.on("tile:add", function(tile, thing)
    if not settings.timers then return end
    local timer = 0
    if thing:getId() == 2129 then -- mwall id
      timer = 20000 -- mwall time
    elseif thing:getId() == 2130 then -- wg id
      timer = 45000 -- wg time
    else
      return
    end

    local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
    if not activeTimers[pos] or activeTimers[pos] < now then    
      activeTimers[pos] = now + timer
    end
    tile:setTimer(activeTimers[pos] - now)
  end, 30)

  EventBus.on("tile:remove", function(tile, thing)
    if not settings.timers then return end
    if (thing:getId() == 2129 or thing:getId() == 2130) and tile:getGround() then
      local pos = tile:getPosition().x .. "," .. tile:getPosition().y .. "," .. tile:getPosition().z
      activeTimers[pos] = nil
      tile:setTimer(0)
    end  
  end, 30)
end

if true then
  -- Anti-kick handler function
  local function antiKickHandler()
    if not settings.antiKick then return end
    local dir = player:getDirection()
    turn((dir + 1) % 4)
    schedule(50, function() turn(dir) end)
  end

  -- Use UnifiedTick if available, fallback to standalone macro
  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("anti_kick", {
      interval = 600000, -- 10 minutes
      priority = UnifiedTick.Priority.IDLE,
      handler = antiKickHandler,
      group = "tools"
    })
  else
    macro(600*1000, antiKickHandler)
  end
end

if true then
  -- Pre-built lookup sets for O(1) body type check
  local knifeBodies = {4286, 4272, 4173, 4011, 4025, 4047, 4052, 4057, 4062, 4112, 4212, 4321, 4324, 4327, 10352, 10356, 10360, 10364}
  local stakeBodies = {4097, 4137, 8738, 18958}
  local fishingBodies = {9582}
  
  local knifeBodiesSet = {}
  local stakeBodiesSet = {}
  local fishingBodiesSet = {}
  
  for _, id in ipairs(knifeBodies) do knifeBodiesSet[id] = true end
  for _, id in ipairs(stakeBodies) do stakeBodiesSet[id] = true end
  for _, id in ipairs(fishingBodies) do fishingBodiesSet[id] = true end
  
  -- Cache for recently failed positions to avoid repeated attempts
  local failedPositions = {}
  local FAILED_POS_TTL = 5000  -- 5 seconds cooldown for failed positions
  
  local function canReachTile(tilePos)
    local playerPos = player:getPosition()
    -- Check if on same floor
    if tilePos.z ~= playerPos.z then return false end
    -- Check distance first (cheap check)
    local dx = math.abs(tilePos.x - playerPos.x)
    local dy = math.abs(tilePos.y - playerPos.y)
    local dist = math.max(dx, dy)
    if dist > 7 then return false end  -- Too far
    if dist <= 1 then return true end  -- Adjacent, always reachable
    -- Check if path exists (more expensive)
    local path = findPath(playerPos, tilePos, 7, {ignoreNonPathable = true, precision = 1, ignoreCreatures = true})
    return path ~= nil and #path > 0
  end
  
  local function getFailedPosKey(pos)
    return pos.x .. "," .. pos.y .. "," .. pos.z
  end
  
  -- Skin Monsters handler function (shared by UnifiedTick and fallback macro)
  local function skinMonstersHandler()
    if not CaveBot or type(CaveBot.isOn) ~= "function" or not CaveBot.isOn() or not settings.stake then return end
    
    local playerPos = player:getPosition()
    local playerZ = playerPos.z
    local hasKnife = findItem(5908)
    local hasStake = findItem(5942)
    local hasFishingRod = findItem(3483)
    
    -- Early exit if no tools
    if not hasKnife and not hasStake and not hasFishingRod then return end
    
    local currentTime = now
    local bestCandidate = nil
    local bestDistance = 100
    
    -- Clean up old failed positions
    for key, expireTime in pairs(failedPositions) do
      if currentTime > expireTime then
        failedPositions[key] = nil
      end
    end
    
    -- Scan only tiles within loot/skin range instead of entire floor
    -- Use a radius scan centered on player (max skin reach is 7 sqm)
    local SKIN_RADIUS = 7
    for dx = -SKIN_RADIUS, SKIN_RADIUS do
      for dy = -SKIN_RADIUS, SKIN_RADIUS do
        local tilePos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerZ}
        local posKey = getFailedPosKey(tilePos)
        
        -- Skip recently failed positions
        if not failedPositions[posKey] then
          local tile = g_map.getTile(tilePos)
          if tile then
            local item = tile:getTopThing()
            if item and item:isContainer() then
              local itemId = item:getId()
              local toolId = nil
              
              if hasKnife and knifeBodiesSet[itemId] then
                toolId = 5908
              elseif hasStake and stakeBodiesSet[itemId] then
                toolId = 5942
              elseif hasFishingRod and fishingBodiesSet[itemId] then
                toolId = 3483
              end
              
              if toolId then
                local dist = math.max(math.abs(dx), math.abs(dy))
                
                if dist < bestDistance then
                  if canReachTile(tilePos) then
                    bestCandidate = { item = item, toolId = toolId, pos = tilePos }
                    bestDistance = dist
                    if dist <= 1 then break end  -- Found adjacent, use immediately
                  else
                    failedPositions[posKey] = currentTime + FAILED_POS_TTL
                  end
                end
              end
            end
          end
        end
      end
      if bestCandidate and bestDistance <= 1 then break end
    end
    
    if bestCandidate then
      if bestDistance <= 1 then
        CaveBot.delay(450)
        SafeCall.useWith(bestCandidate.toolId, bestCandidate.item)
      else
        -- Walk to the corpse first
        CaveBot.walkTo(bestCandidate.pos, 7, {ignoreNonPathable = true, precision = 1})
        CaveBot.delay(300)
      end
    end
  end
  
  -- Use UnifiedTick if available, fallback to standalone macro
  if UnifiedTick and UnifiedTick.register then
    -- Register with UnifiedTick for consolidated tick management
    -- Lower priority since skinning is not combat-critical
    UnifiedTick.register("skin_monsters", {
      interval = 400,
      priority = UnifiedTick.Priority.LOW,
      handler = skinMonstersHandler,
      group = "tools"
    })
  else
    -- Fallback to standalone macro if UnifiedTick not available
    macro(400, skinMonstersHandler)
  end
end

if true then
  onTalk(function(name, level, mode, text, channelId, pos)
    if not settings.oberon then return end
    if mode == 34 then
        if string.find(text, "world will suffer for") then
            say("Are you ever going to fight or do you prefer talking?")
        elseif string.find(text, "feet when they see me") then
            say("Even before they smell your breath?")
        elseif string.find(text, "from this plane") then
            say("Too bad you barely exist at all!") 
        elseif string.find(text, "ESDO LO") then
            say("SEHWO ASIMO, TOLIDO ESD") 
        elseif string.find(text, "will soon rule this world") then
            say("Excuse me but I still do not get the message!") 
        elseif string.find(text, "honourable and formidable") then
            say("Then why are we fighting alone right now?") 
        elseif string.find(text, "appear like a worm") then
            say("How appropriate, you look like something worms already got the better of!") 
        elseif string.find(text, "will be the end of mortal") then
            say("Then let me show you the concept of mortality before it!") 
        elseif string.find(text, "virtues of chivalry") then
            say("Dare strike up a Minnesang and you will receive your last accolade!") 
        end
    end
  end)
end

if true then
  local doorsIds = { 5007, 8265, 1629, 1632, 5129, 6252, 6249, 7715, 7712, 7714, 
                     7719, 6256, 1669, 1672, 5125, 5115, 5124, 17701, 17710, 1642, 
                     6260, 5107, 4912, 6251, 5291, 1683, 1696, 1692, 5006, 2179, 5116, 
                     1632, 11705, 30772, 30774, 6248, 5735, 5732, 5120, 23873, 5736,
                     6264, 5122, 30049, 30042, 7727 }

  function checkForDoors(pos)
    local tile = g_map.getTile(pos)
    if tile then
      local useThing = tile:getTopUseThing()
      if useThing and table.find(doorsIds, useThing:getId()) then
        g_game.use(useThing)
      end
    end
  end

  onKeyPress(function(keys)
    local wsadWalking = modules and modules.game_walking and modules.game_walking.wsadWalking
    if not settings.autoOpenDoors then return end
    local pos = player:getPosition()
    if keys == 'Up' or (wsadWalking and keys == 'W') then
      pos.y = pos.y - 1
    elseif keys == 'Down' or (wsadWalking and keys == 'S') then
      pos.y = pos.y + 1
    elseif keys == 'Left' or (wsadWalking and keys == 'A') then
      pos.x = pos.x - 1
    elseif keys == 'Right' or (wsadWalking and keys == 'D') then
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Q" then
      pos.y = pos.y - 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "E" then
      pos.y = pos.y - 1
      pos.x = pos.x + 1
    elseif wsadWalking and keys == "Z" then
      pos.y = pos.y + 1
      pos.x = pos.x - 1
    elseif wsadWalking and keys == "C" then
      pos.y = pos.y + 1
      pos.x = pos.x + 1
    end
    checkForDoors(pos)
  end)
end

if true then
  local blessed = false
  onTextMessage(function(mode,text) 
    if not settings.bless then return end
    
    text = text:lower()

    if text == "you already have all blessings." then
      blessed = true
    end
  end)
  if settings.bless then
    if player:getBlessings() == 0 then
      say("!bless")
      schedule(2000, function() 
          if g_game.getClientVersion() > 1000 then
            if not blessed and player:getBlessings() == 0 then
                warn("!! Blessings not bought !!")
            end
          end
      end)
    end
  end
end

if true then
  local excluded = {268, 237, 238, 23373, 266, 236, 239, 7643, 23375, 7642, 23374, 5908, 5942} 

  onUseWith(function(pos, itemId, target, subType)
    if settings.reUse and not table.find(excluded, itemId) then
      schedule(50, function()
        item = findItem(itemId)
        if item then
          modules.game_interface.startUseWith(item)
        end
      end)
    end
  end)
end

if true then
  -- Supplies control handler function
  local function suppliesControlHandler()
    if not settings.suppliesControl then return end
    if TargetBot.isOff() then return end
    if CaveBot.isOff() then return end
    if type(hasSupplies()) == 'table' then
        TargetBot.setOff()
    end
  end

  -- Use UnifiedTick if available, fallback to standalone macro
  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("supplies_control", {
      interval = 500,
      priority = UnifiedTick.Priority.LOW,
      handler = suppliesControlHandler,
      group = "tools"
    })
  else
    macro(500, suppliesControlHandler)
  end
end

if true then

  local hold = 0
  local mwHot
  local wgHot

  local candidates = {}
  
  -- Hold MW/WG handler function (shared by UnifiedTick and fallback macro)
  local function holdMwWgHandler()
    mwHot = settings.holdMwHot
    wgHot = settings.holdWgHot
    
    if not settings.holdMwall then return end
      if #candidates == 0 then return end

      for i, pos in pairs(candidates) do
        local tile = g_map.getTile(pos)
        if tile then
          if tile:getText():len() == 0 then 
            table.remove(candidates, i)
          end
          local rune = tile:getText() == "HOLD MW" and 3180 or tile:getText() == "HOLD WG" and 3156
          if tile:canShoot() and not isInPz() and tile:isWalkable() and tile:getTopUseThing():getId() ~= 2130 then
            if math.abs(player:getPosition().x-tile:getPosition().x) < 8 and math.abs(player:getPosition().y-tile:getPosition().y) < 6 then
              return useWith(rune, tile:getTopUseThing())
            end
          end
        end
      end
  end
  
  -- Use UnifiedTick if available, fallback to standalone macro
  local m
  local macroEnabled = true  -- Track enabled state for event handlers
  if UnifiedTick and UnifiedTick.register then
    -- Register with UnifiedTick for consolidated tick management
    UnifiedTick.register("hold_mw_wg", {
      interval = 100,
      priority = UnifiedTick.Priority.HIGH,
      handler = holdMwWgHandler,
      group = "combat"
    })
    -- Create isOff/isOn compatibility functions
    m = {
      isOff = function() return not macroEnabled end,
      isOn = function() return macroEnabled end,
      setOn = function(enabled) 
        macroEnabled = enabled
        UnifiedTick.setEnabled("hold_mw_wg", enabled)
      end
    }
  else
    -- Fallback to standalone macro if UnifiedTick not available
    m = macro(100, holdMwWgHandler)
  end

  -- Consolidated: uses EventBus instead of direct native hooks.
  -- event_bus.lua already filters to isItem() and applies z-change +
  -- tile-burst throttling before emitting.
  EventBus.on("tile:remove", function(tile, thing)
    if not settings.holdMwall then return end
      if thing:getId() ~= 2129 then return end
      if tile:getText():find("HOLD") then
          table.insert(candidates, tile:getPosition())
          local rune = tile:getText() == "HOLD MW" and 3180 or tile:getText() == "HOLD WG" and 3156
          if math.abs(player:getPosition().x-tile:getPosition().x) < 8 and math.abs(player:getPosition().y-tile:getPosition().y) < 6 then
            return useWith(rune, tile:getTopUseThing())
          end
      end
  end, 30)

  EventBus.on("tile:add", function(tile, thing)
    if not settings.holdMwall then return end
      if m.isOff() then return end
      if thing:getId() ~= 2129 then return end
      if tile:getText():len() > 0 then
          table.remove(candidates, table.find(candidates,tile))
      end
  end, 30)

  onKeyDown(function(keys)
    local wsadWalking = modules and modules.game_walking and modules.game_walking.wsadWalking
    if not wsadWalking then return end
    if not settings.holdMwall then return end
    if m.isOff() then return end
    if keys ~= mwHot and keys ~= wgHot then return end
    hold = now

    local tile = getTileUnderCursor()
    if not tile then return end

    if tile:getText():len() > 0 then
        tile:setText("")
    else
        if keys == mwHot then
            tile:setText("HOLD MW")
        else
            tile:setText("HOLD WG")
        end
        table.insert(candidates, tile:getPosition())
    end
  end)

  onKeyPress(function(keys)
    local wsadWalking = modules and modules.game_walking and modules.game_walking.wsadWalking
    if not wsadWalking then return end
    if not settings.holdMwall then return end
    if m.isOff() then return end
    if keys ~= mwHot and keys ~= wgHot then return end

    if (hold - now) < -1000 then
      -- Clear held positions from candidate list instead of scanning entire floor
      for i, cpos in ipairs(candidates) do
        local tile = g_map.getTile(cpos)
        if tile then
          local text = tile:getText()
          if text:find("HOLD") then
            tile:setText("")
          end
        end
      end
      candidates = {}
    end
  end)
end

if true then
  local found
  local function checkPlayers()
    for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
      if spec:isPlayer() and spec:getText() == "" and spec:getPosition().z == posz() and spec ~= player then
          g_game.look(spec)
          found = now
      end
    end
  end
  if settings.checkPlayer then 
    schedule(500, function()
      checkPlayers()
    end)
  end

  onPlayerPositionChange(function(x,y)
    if not settings.checkPlayer then return end
    if zChanging() then
      return
    end
    if x.z ~= y.z then
      schedule(20, function() checkPlayers() end)
    end
  end)

  onCreatureAppear(function(creature)
    if not settings.checkPlayer then return end
    if zChanging() then return end
    if creature:isPlayer() and creature:getText() == "" and creature:getPosition().z == posz() and creature ~= player then
        g_game.look(creature)
        found = now
    end
  end)

  local regex = [[You see ([^\(]*) \(Level ([0-9]*)\)((?:.)* of the ([\w ]*),|)]]
  onTextMessage(function(mode, text)
    if not settings.checkPlayer then return end

    local re = regexMatch(text, regex)
    if #re ~= 0 then
        local name = re[1][2]
        local level = re[1][3]
        local guild = re[1][5] or ""

        if guild:len() > 10 then
          guild = guild:sub(1,10) -- change to proper (last) values
          guild = guild.."..."
        end
        -- determine vocation shorthand safely (default to empty string)
        local voc = ""
        local ltext = text:lower()
        if ltext:find("sorcerer") then
            voc = "MS"
        elseif ltext:find("druid") then
            voc = "ED"
        elseif ltext:find("knight") then
            voc = "EK"
        elseif ltext:find("paladin") then
            voc = "RP"
        elseif ltext:find("monk") then
            voc = "MK" -- handle monk vocation
        end
        local creature = SafeCall.getCreatureByName(name)
        if creature then
            -- include a space before vocation so output is readable; empty `voc` is safe
            creature:setText("\n"..level..(voc ~= "" and (" "..voc) or "").."\n"..guild)
        end
        if found and now - found < 500 then
          modules.game_textmessage.clearMessages()
        end
    end
  end)
end

local function openNextLootContainer()
    if not settings.nextBackpack then return end
    local containers = getContainers()
    local lootCotaniersIds = CaveBot.GetLootContainers()

    for i, container in ipairs(containers) do
      local cId = container:getContainerItem():getId()
      if containerIsFull(container) then
        if table.find(lootCotaniersIds, cId) then
          for _, item in ipairs(container:getItems()) do
            if item:getId() == cId then
              return g_game.open(item, container)
            end
          end
        end
      end
    end
  end
if true then
  onContainerOpen(function(container, previousContainer)
    schedule(100, function()
      openNextLootContainer()
    end)
  end)

  onAddItem(function(container, slot, item, oldItem)
    schedule(100, function()
      openNextLootContainer()
    end)
  end)
end

if true then
  local function forceMarked(creature)
    if target and target() == creature then
        creature:setMarked("red")
        return schedule(333, function() forceMarked(creature) end)
    end
  end

  onAttackingCreatureChange(function(newCreature, oldCreature)
    if not settings.highlightTarget then return end
      if oldCreature then
          oldCreature:setMarked('')
      end
      if newCreature then
          forceMarked(newCreature)
      end
  end)
end

-- Note: SmartHunt, Combat Intelligence, Performance Optimizer, and State Machine
-- modules run automatically in the background to improve bot accuracy.
-- No UI buttons needed - they silently enhance targeting, pathfinding, and combat.
