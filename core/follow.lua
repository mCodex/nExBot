-- Follow Player — party hunt companion
-- Single responsibility: keep bot near leader. MovementCoordinator handles priority.

local Follow = {}

local getClient = nExBot.Shared.getClient
local SC = SafeCreature

-- Config
local config = {
  enabled = false,
  playerName = "",
  followWhileAttacking = true,
  maxDistance = 3,
}

-- State
local state = {
  leaderId = nil,
  leaderCreature = nil,
  leaderPos = nil,
  lastDistance = 0,
  lastKnownPos = nil,
  lastLostTime = 0,
  lastFollowAttempt = 0,
}

local COOLDOWN = 75
local LOST_TIMEOUT = 10000
local PATH_MAX = 25
local PATH_FLAGS = 1 + 16

-- ── Helpers ──────────────────────────────────────────────────────────

local function nowMs()
  return now or (os.time() * 1000)
end

local targetPathfinding = nExBot.target_pathfinding or dofile("/targetbot/target_pathfinding.lua")

local function getGameAttackTarget()
  local Client = getClient()
  if Client and Client.getAttackingCreature then return Client.getAttackingCreature() end
  if g_game and g_game.getAttackingCreature then return g_game.getAttackingCreature() end
  return nil
end

local function isAttacking()
  local Client = getClient()
  if Client and Client.isAttacking then return Client.isAttacking() end
  if g_game and g_game.isAttacking then return g_game.isAttacking() end
  return false
end

local function cancelAttack()
  local Client = getClient()
  if Client and Client.cancelAttack then pcall(Client.cancelAttack) end
end

local function getFollowingCreature()
  local Client = getClient()
  if Client and Client.getFollowingCreature then return Client.getFollowingCreature() end
  if g_game and g_game.getFollowingCreature then return g_game.getFollowingCreature() end
  return nil
end

local function cancelFollow()
  local Client = getClient()
  if Client and Client.cancelFollow then pcall(Client.cancelFollow) end
end

local function startFollow(creature)
  if not creature then return false end
  local Client = getClient()
  local ok = pcall(function()
    if Client and Client.follow then Client.follow(creature)
    elseif g_game and g_game.follow then g_game.follow(creature)
    end
  end)
  return ok
end

-- ── Leader lookup (O(1) cached by ID) ────────────────────────────────

local function findLeader(name)
  if not name or name == "" then return nil end

  -- Re-validate cached creature
  if state.leaderId and state.leaderCreature then
    local ok, alive = pcall(function()
      return not state.leaderCreature:isDead()
    end)
    if ok and alive then
      local pos = SC.getPosition(state.leaderCreature)
      if pos then
        state.leaderPos = pos
        return state.leaderCreature
      end
    end
    state.leaderId = nil
    state.leaderCreature = nil
  end

  -- Lookup by name
  local c = SafeCall.getCreatureByName(name, true)
  if c then
    local okP, isP = pcall(function() return c:isPlayer() end)
    local okL, isL = pcall(function() return c:isLocalPlayer() end)
    if okP and isP and (not okL or not isL) then
      state.leaderId = SC.getId(c)
      state.leaderCreature = c
      state.leaderPos = SC.getPosition(c)
      return c
    end
  end

  return nil
end

-- ── Pathfinding (single path, no fallback chain) ─────────────────────

local function pathTo(leaderPos)
  local lp = ClientService.getLocalPlayer()
  if not lp or not leaderPos then return nil end
  local pp = SC.getPosition(lp)
  if not pp or pp.z ~= leaderPos.z then return nil end
  if targetPathfinding.chebyshev(pp, leaderPos) <= 1 then return {} end

  if g_map and g_map.findPath then
    local ok, result = pcall(function()
      return g_map.findPath(pp, leaderPos, 50, PATH_FLAGS)
    end)
    if ok and result and #result > 0 and #result < PATH_MAX then
      return result
    end
  end

  if findPath then
    local ok, result = pcall(function()
      return findPath(pp, leaderPos, 20, { ignoreCreatures = true, ignoreCost = true })
    end)
    if ok and result then return result end
  end

  return nil
end

-- ── Movement ─────────────────────────────────────────────────────────

local function walkStep(dir)
  local lp = ClientService.getLocalPlayer()
  if not lp or not dir then return false end
  if lp.isWalking and lp:isWalking() then return false end

  if g_game and g_game.forceWalk then
    local ok = pcall(function() g_game.forceWalk(dir) end)
    if ok then return true end
  end
  if lp.walk then
    local ok = pcall(function() lp:walk(dir) end)
    if ok then return true end
  end
  if g_game and g_game.walk then
    local ok = pcall(function() g_game.walk(dir) end)
    if ok then return true end
  end
  return false
end

local function registerFollowIntent(targetPos, confidence)
  if not MovementCoordinator or not MovementCoordinator.Intent then return false end
  local intentType = MovementCoordinator.CONSTANTS
    and MovementCoordinator.CONSTANTS.INTENT
    and MovementCoordinator.CONSTANTS.INTENT.FOLLOW
  if not intentType then return false end

  MovementCoordinator.Intent.register(
    intentType, targetPos, confidence, "party_follow",
    { leader = config.playerName }
  )
  return true
end

-- ── Public API ───────────────────────────────────────────────────────

function Follow.isEnabled()
  return config.enabled
end

function Follow.getConfig()
  return config
end

function Follow.getState()
  return state
end

function Follow.getLeaderPos()
  return state.leaderPos
end

function Follow.getDistance()
  return state.lastDistance
end

function Follow.isNearLeader()
  return state.lastDistance <= config.maxDistance
end

function Follow.setEnabled(enabled)
  config.enabled = enabled
  if not enabled then
    cancelFollow()
    state.leaderId = nil
    state.leaderCreature = nil
    state.leaderPos = nil
    state.lastKnownPos = nil
    state.lastLostTime = 0
  end
end

function Follow.setPlayerName(name)
  config.playerName = name
  state.leaderId = nil
  state.leaderCreature = nil
  state.leaderPos = nil
end

-- ── Main tick (called by macro) ──────────────────────────────────────

function Follow.tick()
  if not config.enabled then return end

  -- Yield to CaveBot when it's walking
  if CaveBot and CaveBot.isOn and CaveBot.isOn() and WaypointEngine and WaypointEngine.isWalking then
    return
  end

  local t = nowMs()
  if (t - state.lastFollowAttempt) < COOLDOWN then return end
  state.lastFollowAttempt = t

  local name = config.playerName and config.playerName:trim() or ""
  if name == "" then return end

  local lp = ClientService.getLocalPlayer()
  if not lp then return end
  local pp = SC.getPosition(lp)
  if not pp then return end

  local leader = findLeader(name)

  if leader then
    local lpos = SC.getPosition(leader)
    if not lpos then return end
    state.leaderPos = lpos
    state.lastKnownPos = lpos
    state.lastLostTime = 0
    state.lastDistance = targetPathfinding.chebyshev(pp, lpos)

    -- Close enough
    if state.lastDistance <= 1 then return end

    -- Beyond max distance — must catch up
    if state.lastDistance > config.maxDistance then
      if isAttacking() and config.followWhileAttacking then
        -- Parallel: walk toward leader while attack persists via ASM
        local path = pathTo(lpos)
        if path and #path > 0 then
          registerFollowIntent(lpos, 0.95)
          walkStep(path[1])
        end
      else
        -- Not attacking or followWhileAttacking off: catch up
        -- Don't cancel attack — g_game.attack() persists through movement server-side
        registerFollowIntent(lpos, 0.95)
        local path = pathTo(lpos)
        if path and #path > 0 then
          walkStep(path[1])
        else
          startFollow(leader)
        end
      end
      return
    end

    -- Within range but not following — try native follow
    local cur = getFollowingCreature()
    local following = cur and SC.getId(cur) == state.leaderId
    if not following and not (lp.isWalking and lp:isWalking()) then
      startFollow(leader)
    end

  else
    -- Leader not visible — walk to last known position
    if state.lastLostTime == 0 then
      state.lastLostTime = t
    end

    local cur = getFollowingCreature()
    if cur and state.leaderId and SC.getId(cur) == state.leaderId then
      state.leaderPos = SC.getPosition(cur)
      return
    end

    if state.lastKnownPos and (t - state.lastLostTime) < LOST_TIMEOUT then
      local path = pathTo(state.lastKnownPos)
      if path and #path > 0 then
        walkStep(path[1])
      end
    end
  end
end

-- ── EventBus listeners ───────────────────────────────────────────────

if EventBus then
  EventBus.on("creature:move", function(creature, oldPos)
    if not config.enabled then return end
    if not state.leaderId then return end
    local cid = SC.getId(creature)
    if cid ~= state.leaderId then return end

    local newPos = SC.getPosition(creature)
    if not newPos then return end
    state.leaderPos = newPos
    state.leaderCreature = creature

    local lp = ClientService.getLocalPlayer()
    if not lp then return end
    local pp = SC.getPosition(lp)
    if not pp then return end

    state.lastDistance = targetPathfinding.chebyshev(pp, newPos)
    if state.lastDistance > 2 then
      Follow.tick()
    end
  end, 30)

  EventBus.on("combat:end", function()
    if not config.enabled then return end
    if not state.leaderId then return end
    schedule(50, function() Follow.tick() end)
  end, 20)
end

-- ── Config persistence ───────────────────────────────────────────────

function Follow.loadConfig()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    local saved = CharacterDB.get("tools.followPlayer")
    if saved then
      config.enabled = saved.enabled or false
      config.playerName = saved.playerName or ""
      config.followWhileAttacking = saved.followWhileAttacking ~= false
      config.maxDistance = saved.maxDistance or 3
    end
  end
end

function Follow.saveConfig()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("tools.followPlayer", {
      enabled = config.enabled,
      playerName = config.playerName,
      followWhileAttacking = config.followWhileAttacking,
      maxDistance = config.maxDistance,
    })
  end
end

nExBot.Follow = Follow
return Follow
