--[[
  Bot-based Tibia 12 features v1.1
  made by Vithrax

  Credits also to:
  - Martín#2318
  - Lee#7725

  Thanks for ideas, graphics, functions, design tips!
  
  br, Vithrax
]]

-- here you can fix incorrect bosses names in cooldown messages
local BOSSES = {
  -- {in message, correct one}
  {"Scarlet Etzel", "Scarlett Etzel"},
  {"Leiden", "Ravenous Hunger"},
  {"Urmahlulu", "Urmahlullu"}
}

-- SESSION MANAGEMENT: Reset hunt data on bot restart/login
-- 
-- This fixes the issue of cached hunts from past sessions persisting.
-- Session-specific data is cleared on each bot initialization.
-- Persistent data (boss cooldowns, custom prices, settings) is preserved.

-- Clear session-specific hunt data (runs on every bot load)
local function resetHuntSession()
  -- Clear session stats (these should NOT persist between logins)
  storage.bestHit = 0
  storage.bestHeal = 0
  
  -- Initialize analyzers if needed
  storage.analyzers = storage.analyzers or {}
  
  -- Clear tracked loot (session-specific)
  storage.analyzers.trackedLoot = {}
  
  -- Clean up expired boss cooldowns (older than 24 hours past their due time)
  if storage.analyzers.trackedBoss then
    local currentTime = os.time()
    local expiredBosses = {}
    
    for bossName, dueTime in pairs(storage.analyzers.trackedBoss) do
      -- If cooldown ended more than 24 hours ago, remove it
      if currentTime - dueTime > 86400 then  -- 24 * 60 * 60 = 86400 seconds
        expiredBosses[#expiredBosses + 1] = bossName
      end
    end
    
    for i = 1, #expiredBosses do
      storage.analyzers.trackedBoss[expiredBosses[i]] = nil
    end
  end
  
  -- Note: We preserve these across sessions:
  -- - storage.analyzers.trackedBoss (boss cooldowns still active)
  -- - storage.analyzers.customPrices (user preferences)
  -- - storage.analyzers.outfits (creature appearances, limited by LRU)
  -- - storage.analyzers.rarityFrames (user preference)
end

-- Reset session on bot initialization
resetHuntSession()

nExBot.CaveBotData = nExBot.CaveBotData or {
  refills = 0,
  rounds = 0,
  time = {},
  lastRefill = os.time(),
  refillTime = {}
}
local lootWorth = 0
local wasteWorth = 0
local balance = 0
local balanceDesc = ""
local hourDesc = ""
local desc = ""
local hour = ""
local launchTime = now
local startExp = exp()
local dmgTable = {}
local healTable = {}
local expTable = {}
local totalDmg = 0
local totalHeal = 0
local dmgDistribution = {}
local first = {l="-", r="0"}
local second = {l="-", r="0"}
local third = {l="-", r="0"}
local fourth = {l="-", r="0"}
local five = {l="-", r="0"}
-- Note: bestHit/bestHeal are reset by resetHuntSession() above
-- We don't restore old values here anymore
local lootedItems = {}
local useData = {}
local usedItems ={}
local lastDataSend = {0, 0}
local killList = {}
local membersData = {}
HuntingSessionStart = os.date('%Y-%m-%d, %H:%M:%S')

if not storage.analyzers then
  storage.analyzers = {
    trackedLoot = {},
    trackedBoss = {},
    outfits = {},
    customPrices = {},
    rarityFrames = true,
  }
end

storage.analyzers = storage.analyzers or {}
storage.analyzers.trackedLoot = storage.analyzers.trackedLoot or {}
storage.analyzers.trackedBoss = storage.analyzers.trackedBoss or {}
storage.analyzers.outfits = storage.analyzers.outfits or {}
storage.analyzers.customPrices = storage.analyzers.customPrices or {}

local trackedLoot = storage.analyzers.trackedLoot

local function getSumStats()
  local totalWaste = 0
  local totalLoot = 0

  for k,v in pairs(membersData) do
    totalWaste = totalWaste + v.waste
    totalLoot = totalLoot + v.loot
  end

  local totalBalance = totalLoot - totalWaste

  return totalWaste, totalLoot, totalBalance
end

local function clipboardData()
  local totalWaste, totalLoot, totalBalance = getSumStats()
  local final = ""

  local first = "Session data: From " .. HuntingSessionStart .." to ".. os.date('%Y-%m-%d, %H:%M:%S')
  local second = "Session: " .. sessionTime()
  local third = "Loot Type: Market"
  local fourth = "Loot " .. format_thousand(totalLoot, true)
  local fifth = "Supplies " .. format_thousand(totalWaste, true)
  local six = "Balance " .. format_thousand(totalBalance, true)

  local t = {first, second, third, fourth, fifth, six}
  for i, string in ipairs(t) do
    final = final.. "\n"..string
  end

  --user data now
  for k,v in pairs(membersData) do
    final = final.. "\n".. k

    final = final.. "\n\tLoot "..v.loot
    final = final.. "\n\tSupplies "..v.waste
    final = final.. "\n\tBalance "..v.balance
    final = final.. "\n\tDamage "..v.damage
    final = final.. "\n\tHealing "..v.heal
  end

  g_window.setClipboardText(final)
end

-- on login
newTimeFormat = function(v) -- v in seconds
  local hours = string.format("%02.f", math.floor(v/3600))
  local mins = string.format("%02.f", math.floor(v/60 - (hours*60)))

  local final = hours.. "h "..mins.."min"
  return final
end

local bossRegex = [[You (?:can|may) challenge ([\w\W]*) again in ([\d]*)]]
onTalk(function(name, level, mode, text, channelId, pos)
  if mode == 34 then
    local re = regexMatch(text, bossRegex)
    local name = re and re[1] and re[1][2]
    local cd = re and re[1] and re[1][3]

    for i=1,#BOSSES do
      local bad = BOSSES[i][1]
      local good = BOSSES[i][2]

      if name == bad then
        name = good
      end
    end

    if not cd then return end

    cd = tonumber(cd) * 60 * 60 -- cd in seconds

    storage.analyzers.trackedBoss[name] = os.time() + cd
  end
end)

-- save outfits
onAttackingCreatureChange(function(newCreature, oldCreature)
  local name = newCreature and newCreature:getName()
  local outfit = newCreature and newCreature:getOutfit()

  if name then
    storage.analyzers.outfits[name] = storage.analyzers.outfits[name] or outfit
  end
end)

--#############################################   UI DONE

-- first, the variables

local console = modules.game_console
local regex = [[ ([^,|^.]+)]]
local noData = {}
local data = {}

local function getColor(v)
    if v >= 10000000 then -- 10kk, red
        return "#FF0000" 
    elseif v >= 5000000 then -- 5kk, orange
        return "#FFA500"
    elseif v >= 1000000 then -- 1kk, yellow
        return "#FFFF00"
    elseif v >= 100000 then -- 100k, purple
        return "#F25AED"
    elseif v >= 10000 then -- 10k, blue
        return "#5F8DF7"
    elseif v >= 1000 then -- 1k, green
        return "#00FF00"
    elseif v >= 50 then
        return "#FFFFFF" -- 50gp, white
    else
      return "#aaaaaa" -- less than 100gp, grey
    end
end

local function formatStr(str)
    if string.starts(str, "a ") then
        str = str:sub(2, #str)
    elseif string.starts(str, "an ") then
      str = str:sub(3, #str)
    end

    local n = getFirstNumberInText and getFirstNumberInText(str)
    if n then
        str = string.split(str, tostring(n))[1]
        str = str:sub(1,#str-1)
    end

    return str:trim()
end

local function getPrice(name)
    name = formatStr(name)
    name = name:lower()
    -- first check custom prices
    if storage.analyzers.customPrices[name] then
      return storage.analyzers.customPrices[name]
    end

    -- if already checked and no data skip looping items.lua
    if noData[name] then
        return 0
    end

    -- maybe was already checked, if so, skip looping items.lua
    if data[name] then
        return data[name]
    end

    -- searching in items.lua - big table, if possible skip
    for k,v in pairs(LootItems) do
        if name == k then
            data[name] = v
            return v
        end
    end

    -- if no data, save it and return 0
    noData[name] = true
    return 0
end

local expGained = function()
  return exp() - startExp
end

function format_thousand(v, comma)
  comma = comma and "," or "."
  if not v then return 0 end
  local s = string.format("%d", math.floor(v))
  local pos = string.len(s) % 3
  if pos == 0 then pos = 3 end
  return string.sub(s, 1, pos)
  .. string.gsub(string.sub(s, pos+1), "(...)", comma.."%1")
end

local expLeft = function()
  local level = lvl()+1
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200) - exp()
end

niceTimeFormat = function(v, seconds) -- v in seconds
  local hours = string.format("%02.f", math.floor(v/3600))
  local mins = string.format("%02.f", math.floor(v/60 - (hours*60)))
  local secs = string.format("%02.f", math.floor(math.fmod(v, 60)))

  local final = string.format('%s:%s%s',hours,mins,seconds and ":"..secs or "")
 return final
end
local uptime
sessionTime = function()
  uptime = math.floor((now - launchTime)/1000)
  return niceTimeFormat(uptime)
end
sessionTime()

local expPerHour = function(calculation)
  local r = 0
  if #expTable > 0 then
      r = exp() - expTable[1]
  else
      return "-"
  end

  if uptime < 15*60 then
      r = math.ceil((r/uptime)*60*60)
  else
      r = math.ceil(r*8)
  end
  if calculation then
      return r
  else
      return format_thousand(r)
  end
end

local function add(t, text, color, last)
    table.insert(t, text)
    table.insert(t, color)
    if not last then
        table.insert(t, ", ")
        table.insert(t, "#FFFFFF")
    end
end

-- Bot Server
local function sendData()
  if BotServer._websocket then
    local totalDmg, totalHeal, lootWorth, wasteWorth, balance = getHuntingData()
    local outfit = player:getOutfit()
    outfit.mount = 0
    local t = {
      totalDmg, 
      totalHeal, 
      balance, 
      hppercent(), 
      manapercent(), 
      outfit, 
      player:isPartyLeader(), 
      lootWorth, 
      wasteWorth,
      modules.game_skills.skillsWindow.contentsPanel.stamina.value:getText(),
      format_thousand(expGained()),
      expPerHour(),
      balanceDesc .. " (" .. hourDesc .. ")",
      sessionTime()
    }

    -- validation
    if lastDataSend.totalDmg ~= t[1] and lastDataSend.totalHeal ~= t[2] then
      BotServer.send("partyHunt", t)
      lastDataSend[1] = t[1]
      lastDataSend[2] = t[2]
    end
  end
end

-- process data
if BotServer._websocket then
  BotServer.listen("partyHunt", function(name, message)
    if message == true then
      sendData()
    elseif message == false then
      resetAnalyzerSessionData()
    else
      membersData[name] = {
        damage = message[1], 
        heal = message[2], 
        balance = message[3], 
        hp = message[4], 
        mana = message[5], 
        outfit = message[6], 
        leader = message[7], 
        loot = message[8], 
        waste = message[9],
        stamina = message[10],
        expGained = message[11],
        expH = message[12],
        balanceH = message[13],
        session = message[14]
      }
    end
  end)
end

-- empty UI refresh hooks: the standalone Analyzer windows are retired, the
-- data still lives in the tables above.
function refreshKills() end
function refreshLoot() end
function refreshWaste() end

-- drop tracker: name lookup for tracked item ids (kept in sync by the engine)
local trackedLootNames = {}
local function refreshTrackedLootNames()
  trackedLootNames = {}
  for id in pairs(trackedLoot) do
    local nid = tonumber(id)
    local name
    if nid == 3031 then
      name = "gold coin"
    elseif nid == 3035 then
      name = "platinum coin"
    elseif nid == 3043 then
      name = "crystal coin"
    elseif Item.create then
      local ok, market = pcall(function() return Item.create(nid):getMarketData() end)
      name = ok and market and market.name or nil
    end
    if name then trackedLootNames[name:lower()] = id end
  end
end
refreshTrackedLootNames()

local nameRegex = [[Loot of (?:an |a |the |)([^:]+)]]
onTextMessage(function(mode, text)
    if not text:find("Loot of") and not text:find("The following items are available in your reward chest") then return end
    local name

    -- adding monster to killed list
    if text:find("Loot of") then
      local match = regexMatch(text, nameRegex)
      if match and match[1] and match[1][2] then
        name = match[1][2]
        if not killList[name] then
          killList[name] = 1
        else
          killList[name] = killList[name] + 1
        end
        refreshKills()
      end
    end
    -- variables
    local split = string.split(text, ":")
    local re = regexMatch(split[2], regex)
    local combinedWorth = 0
    local formatted
    local div
    local t = {}
    local messageT = {}

    -- add timestamp, creature part and color it as white
    add(t, os.date('%H:%M') .. ' ' .. split[1]..": ", "#FFFFFF", true)
    add(messageT, split[1]..": ", "#FFFFFF", true)    

    -- main part
    if re ~= 0 then
        for i=1,#re do
            local data = re[i][2] -- each looted item
            local formattedLoot = regexMatch(data, [[(^[^(]+)]])[1][1]
            formattedLoot = formattedLoot:trim()
            local amount = getFirstNumberInText and getFirstNumberInText(formattedLoot) -- amount found in data
            local price = amount and getPrice(formattedLoot) * amount or getPrice(formattedLoot) -- if amount then multity price, else just take price
            local color = getColor(price) -- generate hex string based off price
            local messageColor = getColor(getPrice(formattedLoot))

            combinedWorth = combinedWorth + price -- add all prices to calculate total worth

            add(t, data, color, i==#re)
            add(messageT, data, color, i==#re)

            --drop tracker
            if formattedLoot then
              for key, id in pairs(trackedLootNames) do
                if formattedLoot:find(key) then
                  trackedLoot[id] = (trackedLoot[id] or 0) + (amount or 1)
                end
              end
            end
        end
    end

    -- format total worth so it wont look obnoxious
    if combinedWorth >= 1000000 then
        div = combinedWorth/1000000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "kk"
    elseif combinedWorth >= 1000 then
        div = combinedWorth/1000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "k"
    else
        formatted = combinedWorth .. "gp"
    end

    if modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:getText() == text then
      modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:setColoredText(messageT)
      schedule(math.max(#text * 50, 2000), function() 
        modules.game_textmessage.messagesPanel.centerTextMessagePanel.highCenterLabel:setVisible(false)
      end)
    end

    -- add total worth to string
    add(t, " - (", "#FFFFFF", true)
    add(t, formatted, getColor(combinedWorth), true)
    add(t, ")", "#FFFFFF", true)

end)

local function niceFormat(v)
  local div
  local formatted
    if v >= 10000000 then
      div = v/10000000
      formatted = math.ceil(div) .. "M"
    elseif v >= 1000000 then
      div = v/1000000
      formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "M"
    elseif v >= 10000 then
      div = v/1000
      formatted = math.floor(div) .. "k"
    elseif v >= 1000 then
        div = v/1000
        formatted = math.floor(div) .. "." .. math.floor(div * 10) % 10 .. "k"
    else
        formatted = v
    end
    return formatted
end

resetAnalyzerSessionData = function()
    nExBot.CaveBotData = nExBot.CaveBotData or {
      refills = 0,
      rounds = 0,
      time = {},
      lastRefill = os.time(),
      refillTime = {}
    }
    launchTime = now
    startExp = exp()
    dmgTable = {}
    healTable = {}
    expTable = {}
    totalDmg = 0
    totalHeal = 0
    dmgDistribution = {}
    first = {l="-", r="0"}
    second = {l="-", r="0"}
    third = {l="-", r="0"}
    fourth = {l="-", r="0"}
    five = {l="-", r="0"}
    lootedItems = {}
    useData = {}
    usedItems ={}
    killList = {}
    HuntingSessionStart = os.date('%Y-%m-%d, %H:%M:%S')
end

local function getFrame(v)
  if v >= 1000000 then
      return '/images/ui/rarity_gold'
  elseif v >= 100000 then
      return '/images/ui/rarity_purple'
  elseif v >= 10000 then
      return '/images/ui/rarity_blue'
  elseif v >= 1000 then
      return '/images/ui/rarity_green'
  else
      return '/images/ui/item'
  end
end

displayCondition = function(menuPosition, lookThing, useThing, creatureThing)
  if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
    return true
  end
end
local interface = modules.game_interface

-- Throttle setFrames to prevent slow macro warnings
local lastSetFramesTime = 0
local SET_FRAMES_THROTTLE = 200 -- ms between updates

local function setFrames()
  if not storage.analyzers.rarityFrames then return end
  
  -- Throttle to prevent excessive calls
  if now - lastSetFramesTime < SET_FRAMES_THROTTLE then return end
  lastSetFramesTime = now
  
  for _, container in pairs(getContainers()) do
      local window = container.itemsPanel
      for i, child in pairs(window:getChildren()) do
          local id = child:getItemId()
          local price = 0

          if id ~= 0 then -- there's item
              local item = Item.create(id)
              local name = item:getMarketData().name:lower()
              price = getPrice(name)

              -- set rarity frame
              child:setImageSource(getFrame(price))
          else -- empty widget
              -- revert any possible changes
              child:setImageSource("/images/ui/item")
          end
          child.onHoverChange = function(widget, hovered)
            if id == 0 or not hovered then
              return interface.removeMenuHook('analyzer')
            end
            interface.addMenuHook('analyzer', 'Price:', function() end, displayCondition, price)          
        end
      end
  end 
end 
setFrames()

onContainerOpen(function(container, previousContainer)
  setFrames()
end)

onAddItem(function(container, slot, item, oldItem)
  setFrames()
end)

onRemoveItem(function(container, slot, item)
  setFrames()
end)

onContainerUpdateItem(function(container, slot, item, oldItem)
  setFrames()
end)

function smallNumbers(n)
  if n >= 10 ^ 6 then
      return string.format("%.1fkk", n / 10 ^ 6)
  elseif n >= 10 ^ 3 then
      return string.format("%.1fk", n / 10 ^ 3)
  else
      return tostring(n)
  end
end

local timeToLevel = function()
    local t = 0
    if expPerHour(true) == 0 or expPerHour() == "-" then
        return "-"
    else
        t = expLeft()/expPerHour(true)
        return niceTimeFormat(math.ceil(t*60*60))
    end
end

local sumT = function(t)
    local s = 0
    for i,v in pairs(t) do
        s = s + v.d
    end
    return s
end

local valueInSeconds = function(t)
    local d = 0
    local time = 0
    if #t > 0 then
        for i, v in ipairs(t) do
            if now - v.t <= 3000 then
                if time == 0 then
                    time = v.t
                end
                d = d + v.d
            else
              table.remove(t, 1)
            end
        end
    end
    return math.ceil(d/((now-time)/1000))
end

local regex = "You lose ([0-9]*) hitpoints due to an attack by ([a-z]*) ([a-z A-z-]*)" 
onTextMessage(function(mode, text)
  local value = getFirstNumberInText and getFirstNumberInText(text)
    if mode == 21 and value then -- damage dealt
      totalDmg = totalDmg + value
        table.insert(dmgTable, {d = value, t = now})
        if value > storage.bestHit then
            storage.bestHit = value
        end
    end
    if mode == 23 and value then -- healing
      totalHeal = totalHeal + value
        table.insert(healTable, {d = value, t = now})
        if value > storage.bestHeal then
            storage.bestHeal = value
        end
    end

    -- damage distribution part
    if text:find("You lose") then
      local data = regexMatch(text, regex)[1]
      if data then
        local monster = data[4]
        local val = data[2]
        table.insert(dmgDistribution, {v=val,m=monster,t=now})
      end
    end
end)

function capitalFistLetter(str)
  return (string.gsub(str, "^%l", string.upper))
end

-- tables maintance
macro(500, function()
  local dmgFinal = {}
  local labelTable = {}
  local dmgSum = 0
    table.insert(expTable, exp())
    if #expTable > 15*60 then
        table.remove(expTable, 1)
    end

    -- Reverse-iterate to safely remove expired entries
    for i = #dmgDistribution, 1, -1 do
      local v = dmgDistribution[i]
      if now - v.t > 60*1000*10 then
        table.remove(dmgDistribution, i)
      else
        dmgSum = dmgSum + v.v
        if not dmgFinal[v.m] then
          dmgFinal[v.m] = v.v
        else
          dmgFinal[v.m] = dmgFinal[v.m] + v.v
        end
      end
    end

    first = dmgFinal[1] or {l="-", r="0"}
    second = dmgFinal[2] or {l="-", r="0"}
    third = dmgFinal[3] or {l="-", r="0"}
    fourth = dmgFinal[4] or {l="-", r="0"}
    five = dmgFinal[5] or {l="-", r="0"}

    for k,v in pairs(dmgFinal) do
      table.insert(labelTable, {m=k, d=tonumber(v)})
    end

    table.sort(labelTable, function(a,b) return a.d > b.d end)

    for i,v in pairs(labelTable) do
      local val = math.floor((v.d/dmgSum)*100) .. "%"
      local words = string.split(v.m, " ")
      local name = ""
      for i, word in ipairs(words) do
        name = name .. " " .. capitalFistLetter(word)
      end
      name = name:len() < 20 and name or name:sub(1,17).."..."
      name = name:trim()..": "
      if i == 1 then
        first = {l=name, r=val}
      elseif i == 2 then
        second = {l=name, r=val}
      elseif i == 3 then
        third = {l=name, r=val}
      elseif i == 4 then
        fourth = {l=name, r=val}
      elseif i == 5 then
        five = {l=name, r=val}
      else
        break
      end
    end
end)

-- loot analyzer
-- adding
local containers = CaveBot.GetLootContainers()
local lastCap = freecap()
onAddItem(function(container, slot, item, oldItem)
  if not table.find(containers, container:getContainerItem():getId()) then return end
  if isInPz() then return end
  if slot > 0 then return end 
  if freecap() >= lastCap then return end
  local name = item:getId()
  local tmpname = item:getId() == 3031 and "gold coin" or item:getId() == 3035 and "platinum coin" or item:getId() == 3043 and "crystal coin" or item:getMarketData().name
  if not lootedItems[name] then
    lootedItems[name] = { count = item:getCount(), name = tmpname }
  else
    lootedItems[name].count =  lootedItems[name].count + item:getCount()
  end
  lastCap = freecap()
end)

onContainerUpdateItem(function(container, slot, item, oldItem)
  if not table.find(containers, container:getContainerItem():getId()) then return end
  if not oldItem then return end
  if isInPz() then return end 
  if freecap() == lastCap then return end
  
  local tmpname = item:getId() == 3031 and "gold coin" or item:getId() == 3035 and "platinum coin" or item:getId() == 3043 and "crystal coin" or item:getMarketData().name
  local amount = item:getCount() - oldItem:getCount()
  if amount < 0 then
    return
  end
  local name = item:getId()
  if not lootedItems[name] then
      lootedItems[name] = { count = amount, name = tmpname }
  else
      lootedItems[name].count = lootedItems[name].count + amount
  end
  lastCap = freecap()
end)

-- ammo
local ammo = {16143, 763, 761, 7365, 3448, 762, 21470, 7364, 14251, 3447, 3449, 15793, 25757, 774, 35901, 6528, 7363, 3450, 16141, 25758, 14252, 3446, 16142, 35902}
onContainerUpdateItem(function(container, slot, item, oldItem)
  local id = item:getId()
  if not table.find(ammo, id) then return end
  local newCount = item:getCount()
  local oldCount = oldItem:getCount()
  local name = item:getMarketData().name

  if oldCount - newCount == 1 then
    if not usedItems[id] then
      usedItems[id] = { count = 1, name = name}
    else
      usedItems[id].count = usedItems[id].count + 1
    end
  end
end)

-- waste
local regex3 = [[\d ([a-z A-Z]*)s...]]
local lackOfData = {}
onTextMessage(function(mode, text)
  text = text:lower()
  if not text:find("using one of") then return end

  local amount = getFirstNumberInText and getFirstNumberInText(text)
  local re = regexMatch(text, regex3)
  local name = re[1][2]
  local id = WasteItems[name]

  if not id then

    if not lackOfData[name] then
      lackOfData[name] = true
      print("[Analyzer] no data for item: "..name.. "inside items.lua -> WasteItems")
    end

    return
  end

  if not useData[name] then
    useData[name] = amount
  else
    if math.abs(useData[name]-amount) == 1 then
      useData[name] = amount
      if not usedItems[id] then
        usedItems[id] = { count = 1, name = name}
      else
        usedItems[id].count = usedItems[id].count + 1
      end
    else
      useData[name] = amount
    end
  end
end)
function bottingStats()
  lootWorth = 0
  wasteWorth = 0
  for k, v in pairs(lootedItems) do
    if LootItems[v.name] then
      lootWorth = lootWorth + (LootItems[v.name]*v.count)
    end
  end
  for k, v in pairs(usedItems) do
    if LootItems[v.name] then
      wasteWorth = wasteWorth + (LootItems[v.name]*v.count)
    end
  end
  balance = lootWorth - wasteWorth

  return lootWorth, wasteWorth, balance
end

function bottingLabels(lootWorth, wasteWorth, balance)
  balanceDesc = nil
  hourDesc = nil
  desc = nil

  if balance >= 1000000 or balance <= -1000000 then
    desc = balance / 1000000
    balanceDesc = math.floor(desc) .. "." .. math.floor(desc * 10) % 10 .. "kk"
  elseif balance >= 1000 or balance <= -1000 then
    desc = balance / 1000
    balanceDesc = math.floor(desc) .. "." .. math.floor(desc * 10) % 10 .."k"
  else
    balanceDesc = balance .. "gp"
  end

  hour = hourVal(balance)
  if hour >= 1000000 or hour <= -1000000 then
    desc = balance / 1000000
    hourDesc = math.floor(hourVal(desc)) .. "." .. math.floor(hourVal(desc) * 10) % 10 .. "kk/h"
  elseif hour >= 1000 or hour <= -1000 then
    desc = balance / 1000
    hourDesc = math.floor(hourVal(desc)) .. "." .. math.floor(hourVal(desc) * 10) % 10 .. "k/h"
  else
    hourDesc = math.floor(hourVal(balance)) .. "gp/h"
  end

  return balanceDesc, hourDesc
end

function getHuntingData()
  local lootWorth, wasteWorth, balance = bottingStats()
  return totalDmg, totalHeal, lootWorth, wasteWorth, balance
end

function hourVal(v)
  v = v or 0
  if not uptime or uptime <= 0 then return 0 end
  return (v/uptime)*3600
end

function avgTable(t)
  if type(t) ~= 'table' then return 0 end
  local val, count = 0, 0
  for _,v in pairs(t) do
    if type(v) == 'number' then
      val = val + v
      count = count + 1
    end
  end
  if count == 0 then return 0 end
  return val / count
end

function damageHour()
  if uptime < 5*60 then
    return totalDmg
  else
    return hourVal(totalDmg)
  end
end

function healHour()
  if uptime < 5*60 then
    return totalHeal
  else
    return hourVal(totalHeal)
  end
end

function wasteHour()
  local lootWorth, wasteWorth, balance = bottingStats()
  if uptime < 5*60 then
    return wasteWorth
  else
    return hourVal(wasteWorth)
  end
end

function lootHour()
  local lootWorth, wasteWorth, balance = bottingStats()
  if uptime < 5*60 then
    return lootWorth
  else
    return hourVal(lootWorth)
  end
end

--bestdps/hps
local bestDPS = 0
local bestHPS = 0
--main loop
macro(500, function()
    local lootWorth, wasteWorth, balance = bottingStats()
    bottingLabels(lootWorth, wasteWorth, balance)

    -- hps and dps
    local curHPS = valueInSeconds(healTable)
    local curDPS = valueInSeconds(dmgTable)

    bestHPS = bestHPS > curHPS and bestHPS or curHPS
    bestDPS = bestDPS > curDPS and bestDPS or curDPS
end)

--party hunt analyzer
macro(2000, function()
  if not BotServer._websocket then return end

  -- send data
  if storage.sendPartyAnalyzerData then
    sendData()
  end
end)

-- public functions
-- global namespace
Analyzer = {}

Analyzer.showWindow = function()
  -- windows retired; navigation moved to the shell "Analyzer" page
end

Analyzer.hideWindow = function()
end

Analyzer.getKillsAmount = function(name)
  return killList[name] or 0
end

Analyzer.getLootedAmount = function(nameOrId)
  if type(nameOrId) == "number" then
    return lootedItems[nameOrId].count or 0
  else
    local nameOrId = nameOrId:lower()
    for k,v in pairs(lootedItems) do
      if v.name == nameOrId then
        return v.count
      end
    end
  end
  return 0
end

Analyzer.getTotalProfit = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return lootWorth
end

Analyzer.getTotalWaste = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return wasteWorth
end

Analyzer.getBalance = function()
  local lootWorth, wasteWorth, balance = bottingStats()

  return balance
end

Analyzer.getXpGained = function()
  return expGained()
end

Analyzer.getXpHour = function()
  return expPerHour()
end

Analyzer.getTimeToNextLevel = function()
  return timeToLevel()
end

Analyzer.getCaveBotStats = function()
  local round = {}
  local refill = {}
  for k, v in pairs(usedItems) do
    round[k] = math.floor(v.count / (nExBot.CaveBotData.rounds + 1))
    refill[k] = math.floor(v.count / (nExBot.CaveBotData.refills + 1))
  end

  return {
    totalRounds = nExBot.CaveBotData.rounds,
    avRoundTime = niceTimeFormat(avgTable(nExBot.CaveBotData.time), true),
    totalRefills = nExBot.CaveBotData.refills,
    avRefillTime = niceTimeFormat(avgTable(nExBot.CaveBotData.refillTime), true),
    lastRefill = niceTimeFormat(os.difftime(os.time() - nExBot.CaveBotData.lastRefill), true),
    roundSupplies = round, -- { [id] = amount, [id2] = amount ...}
    refillSupplies = refill -- { [id] = amount, [id2] = amount ...}
  }
end

-- shell read APIs: return plain tables backed by the engine data above

Analyzer.getHuntStats = function()
  local lootWorth, wasteWorth, balance = bottingStats()
  local balanceDesc, hourDesc = bottingLabels(lootWorth, wasteWorth, balance)
  local kills = {}
  for k, v in pairs(killList) do
    kills[#kills + 1] = { name = k, count = v }
  end
  table.sort(kills, function(a, b) return a.count > b.count end)

  return {
    sessionTime = sessionTime(),
    xpGained = expGained(),
    xpHour = expPerHour(),
    loot = lootWorth,
    supplies = wasteWorth,
    balance = balance,
    balanceLabel = balanceDesc .. " (" .. hourDesc .. ")",
    damage = totalDmg,
    damageHour = damageHour(),
    healing = totalHeal,
    healingHour = healHour(),
    kills = kills,
  }
end

Analyzer.getLootStats = function()
  local lootWorth, wasteWorth, balance = bottingStats()
  local items = {}
  for k, v in pairs(lootedItems) do
    items[#items + 1] = { id = tonumber(k), name = v.name, count = v.count }
  end
  table.sort(items, function(a, b) return a.count > b.count end)

  return { loot = lootWorth, lootHour = lootHour(), items = items }
end

Analyzer.getSupplyStats = function()
  local lootWorth, wasteWorth, balance = bottingStats()
  local items = {}
  for k, v in pairs(usedItems) do
    items[#items + 1] = { id = tonumber(k), name = v.name, count = v.count }
  end
  table.sort(items, function(a, b) return a.count > b.count end)

  return { supplies = wasteWorth, suppliesHour = wasteHour(), items = items }
end

Analyzer.getImpactStats = function()
  local distribution = {}
  local all = { first, second, third, fourth, five }
  for i, entry in ipairs(all) do
    distribution[i] = { name = entry.l, value = entry.r }
  end

  return {
    damage = totalDmg,
    bestDps = bestDPS,
    bestHit = storage.bestHit,
    healing = totalHeal,
    bestHps = bestHPS,
    bestHeal = storage.bestHeal,
    distribution = distribution,
  }
end

Analyzer.getXpStats = function()
  return {
    xpGained = expGained(),
    xpHour = expPerHour(),
    nextLevel = timeToLevel(),
    xpLeft = expLeft(),
  }
end

Analyzer.getPartyStats = function()
  local totalWaste, totalLoot, totalBalance = getSumStats()
  local members = {}
  for k, v in pairs(membersData) do
    members[#members + 1] = {
      name = k,
      loot = v.loot,
      supplies = v.waste,
      balance = v.balance,
      damage = v.damage,
      heal = v.heal,
    }
  end
  table.sort(members, function(a, b) return a.name < b.name end)

  return {
    sessionTime = sessionTime(),
    loot = totalLoot,
    supplies = totalWaste,
    balance = totalBalance,
    sendData = storage.sendPartyAnalyzerData,
    members = members,
  }
end

Analyzer.setSendPartyData = function(enabled)
  storage.sendPartyAnalyzerData = not not enabled
  return storage.sendPartyAnalyzerData
end

Analyzer.getDropTracker = function()
  local items = {}
  for k, v in pairs(trackedLoot) do
    items[#items + 1] = { id = tonumber(k) or 0, count = v }
  end
  table.sort(items, function(a, b) return a.count > b.count end)
  return items
end

Analyzer.addDropTrackerItem = function(id)
  id = tonumber(id)
  if not id or id <= 0 then return false end
  if trackedLoot[tostring(id)] then return false end
  trackedLoot[tostring(id)] = 0
  refreshTrackedLootNames()
  return true
end

Analyzer.resetDropTrackerItem = function(id)
  trackedLoot[tostring(id)] = 0
end

Analyzer.removeDropTrackerItem = function(id)
  trackedLoot[tostring(id)] = nil
  refreshTrackedLootNames()
end

Analyzer.getBossTracker = function()
  local bosses = {}
  for bossName, dueTime in pairs(storage.analyzers.trackedBoss) do
    bosses[#bosses + 1] = {
      name = bossName,
      dueTime = dueTime,
      timeLeft = os.difftime(dueTime, os.time()),
    }
  end
  table.sort(bosses, function(a, b) return a.timeLeft < b.timeLeft end)
  return bosses
end

Analyzer.getCustomPrices = function()
  return storage.analyzers.customPrices
end

Analyzer.setCustomPrice = function(name, price)
  name = tostring(name or ""):lower()
  price = tonumber(price)
  if name == "" or not price or price < 0 then return false end
  storage.analyzers.customPrices[name] = price
  noData[name] = nil
  data[name] = nil
  return true
end

Analyzer.removeCustomPrice = function(name)
  storage.analyzers.customPrices[tostring(name or ""):lower()] = nil
  noData[name] = nil
  data[name] = nil
end

Analyzer.getRarityFrames = function()
  return storage.analyzers.rarityFrames
end

Analyzer.setRarityFrames = function(enabled)
  storage.analyzers.rarityFrames = not not enabled
  setFrames()
  return storage.analyzers.rarityFrames
end