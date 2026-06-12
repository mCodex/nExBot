CaveBot.Extensions.StandLure = {}
local enable = nil

local getClient = nExBot.Shared.getClient
local pathCache = { key = nil, at = 0, withoutMonsters = nil, withMonsters = nil }

local function nowMs()
    if nExBot and nExBot.Shared and nExBot.Shared.nowMs then
        return nExBot.Shared.nowMs()
    end
    if now then return now() end
    return os.time() * 1000
end

local function posKey(pos)
    if not pos then return "unknown" end
    return tostring(pos.x) .. ":" .. tostring(pos.y) .. ":" .. tostring(pos.z)
end

local function actionLimiter()
    return BotCore and BotCore.ActionRateLimiter
end

local function throttleRetry(key, interval, actionType)
    local limiter = actionLimiter()
    if not limiter or not limiter.allow then return true end
    local ok, remaining = limiter.allow("rushlure:" .. key, interval, actionType)
    if not ok then
        delay(math.max(remaining or 50, 50))
        return false
    end
    return true
end

local function getCachedPaths(fromPos, toPos)
    local key = posKey(fromPos) .. ">" .. posKey(toPos)
    local t = nowMs()
    if pathCache.key == key and (t - pathCache.at) < 200 then
        return pathCache.withoutMonsters, pathCache.withMonsters
    end

    pathCache.key = key
    pathCache.at = t
    pathCache.withoutMonsters = findPath(fromPos, toPos, 30, { ignoreFields = true, ignoreNonPathable = true, ignoreCreatures = true, precision = 0})
    pathCache.withMonsters = findPath(fromPos, toPos, 30, { ignoreFields = true, ignoreNonPathable = true, ignoreCreatures = false, precision = 0 })
    return pathCache.withoutMonsters, pathCache.withMonsters
end

-- Use Directions module for direction offsets (DRY: SSoT is constants/directions.lua)
local function modPos(dir)
    local offset = Directions.DIR_TO_OFFSET[dir]
    if offset then
        return {offset.x, offset.y}
    end
    return {0, 0}
end
local function reset(delay)
    if type(Supplies.hasEnough()) == 'table' then
        return
    end
    delay = delay or 0
    CaveBot.delay(delay)
    if delay == nil then
        enable = nil
    end
end

local resetRetries = false
CaveBot.Extensions.StandLure.setup = function()
    CaveBot.registerAction(
        "rushlure",
        "#FF0090",
        function(value, retries)
            local nextPos = nil
            local data = string.split(value, ",")
            if not data[1] then
                warn("Invalid cavebot lure action value. It should be position (x,y,z), delay(ms) is: " .. value)
                return false
            end

            if type(Supplies.hasEnough()) == 'table' then -- do not execute if no supplies
                return false
            end

            local pos = {x = tonumber(data[1]), y = tonumber(data[2]), z = tonumber(data[3])}

            local delayTime = data[4] and tonumber(data[4]) or 1000
            if not data[5] then
                enable = nil
            elseif data[5] == "yes" then
                enable = true
            else
                enable = false
            end

            delay(100)

            if retries > 50 and not resetRetries then
                reset()
                warn("[Rush Lure] Too many tries, can't reach position")
                return false  -- can't stand on tile
            end

            if resetRetries then
                resetRetries = false
            end

            if distanceFromPlayer(pos) > 30 then
                reset()
                return false -- not reachable
            end

            local playerPos = player:getPosition()
            local pathWithoutMonsters, pathWithMonsters = getCachedPaths(playerPos, pos)

            if not pathWithoutMonsters then
                reset()
                warn("[Rush Lure] No possible path to reach position, skipping.")
                return false -- spot is unreachable
            elseif pathWithoutMonsters and not pathWithMonsters then
                local foundMonster = false
                for i, dir in ipairs(pathWithoutMonsters) do
                    local dirs = modPos(dir)
                    nextPos = nextPos or {x = playerPos.x, y = playerPos.y, z = playerPos.z}
                    nextPos.x = nextPos.x + dirs[1]
                    nextPos.y = nextPos.y + dirs[2]

                    local Client = getClient()
                    local tile = (Client and Client.getTile) and Client.getTile(nextPos) or (g_map and g_map.getTile(nextPos))
                    if tile then
                        local hasCreature = tile.hasCreature and tile:hasCreature()
                        if hasCreature then
                            local creature = tile:getCreatures()[1]
                            local hppc = creature:getHealthPercent()
                            if creature:isMonster() and (hppc and hppc > 0) and (oldTibia or creature:getType() < 3) then
                                local path = findPath(playerPos, creature:getPosition(), 7, { ignoreNonPathable = true, precision = 1 })
                                if path then
                                    creature:setMarked('#00FF00')
                                    local attackingCreature = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature())
                                    if attackingCreature ~= creature then
                                        if not throttleRetry("attack-blocker", 350, "attack") then return "retry" end
                                        attack(creature)
                                    end
                                    if not throttleRetry("chase-mode", 300, "default") then return "retry" end
                                    if Client and Client.setChaseMode then Client.setChaseMode(1) elseif g_game then g_game.setChaseMode(1) end
                                    resetRetries = true
                                    delay(200)
                                    return "retry"
                                end
                            end
                        end
                    end
                end

                local Client = getClient()
                local attackingCreature = (Client and Client.getAttackingCreature) and Client.getAttackingCreature() or (g_game and g_game.getAttackingCreature())
                if not attackingCreature then
                    reset()
                    warn("[Rush Lure] No path, no blocking monster, skipping.")
                    return false -- no other way
                end
            end

            -- reaching position, delay targetbot in process
            if not CaveBot.MatchPosition(pos, 0) then
                TargetBot.delay(300)
                if not throttleRetry("walk:" .. posKey(pos), 250, "walk") then return "retry" end
                CaveBot.walkTo(pos, 30, { ignoreCreatures = false, ignoreFields = true, ignoreNonPathable = true, precision = 0})
                delay(200)
                resetRetries = true
                return "retry"
            end

            TargetBot.setOn()
            reset(delayTime)
            return true
        end
    )

    CaveBot.Editor.registerAction(
        "rushlure",
        "rush lure",
        {
            value = function()
                return posx() .. "," .. posy() .. "," .. posz() .. ",1000"
            end,
            title = "Stand Lure",
            description = "Run to position(x,y,z), delay(ms), targetbot on/off (yes/no)",
            multiline = false,
            validation = [[\d{1,5},\d{1,5},\d{1,2},\d{1,5}(?:,(yes|no)$|$)]]
        }
    )
end

local next = false
schedule(5, function() -- delay because cavebot.lua is loaded after this file
    local function resolveCaveBotList()
        -- try CaveBotList() if defined, else fallback to CaveBot.actionList
        local ok, l = pcall(function()
            if type(CaveBotList) == "function" then return CaveBotList() end
            return nil
        end)
        if ok and l then return l end
        if CaveBot and CaveBot.actionList then return CaveBot.actionList end
        return nil
    end

    local function attachHandler(list)
        modules.game_bot.connect(list, {
            onChildFocusChange = function(widget, newChild, oldChild)

                if oldChild and oldChild.action == "rushlure" then
                    next = true
                    return
                end

                if next then
                    if enable then
                        TargetBot.setOn()
                    elseif enable == false then
                        TargetBot.setOff()
                    end
                    
                    enable = nil -- reset
                    next = false
                end
            end
        })
    end

    local list = resolveCaveBotList()
    if list then
        attachHandler(list)
    else
        -- try again after short delay
        schedule(100, function()
            local l2 = resolveCaveBotList()
            if l2 then
                attachHandler(l2)
            else
                warn("[StandLure] CaveBot list not available; handler not attached")
            end
        end)
    end
end)