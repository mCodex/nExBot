--[[
  Outfit Cloner - Clone player outfits via right-click menu
  
  Features:
  - Clone Outfit: Copies the full outfit (type, colors, addons, mount)
  - Copy Colors: Copies only the outfit colors (head, body, legs, feet)
  
  Usage: CTRL + Right-click on any player to see the options
  
  Architecture: DRY, KISS, SOLID, SRP - minimal, focused, efficient
]]

-- ============================================================================
-- PURE OUTFIT FUNCTIONS
-- ============================================================================

-- Get the current player's outfit
local function getPlayerOutfit()
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    return player:getOutfit()
end

-- Build a full outfit table from a creature's outfit
local function buildFullOutfit(sourceOutfit)
    if not sourceOutfit then return nil end
    
    local outfit = {
        head = sourceOutfit.head or 0,
        body = sourceOutfit.body or 0,
        legs = sourceOutfit.legs or 0,
        feet = sourceOutfit.feet or 0,
        addons = sourceOutfit.addons or 0
    }
    
    -- Include type if available
    if sourceOutfit.type then
        outfit.type = sourceOutfit.type
    end
    
    -- Include mount if available
    if sourceOutfit.mount then
        outfit.mount = sourceOutfit.mount
    end
    
    return outfit
end

-- Build a colors-only outfit (preserve player's own type/addons/mount)
local function buildColorsOnlyOutfit(sourceOutfit)
    if not sourceOutfit then return nil end
    
    local currentOutfit = getPlayerOutfit()
    if not currentOutfit then return nil end
    
    -- Keep current type, addons, mount - only copy colors
    local outfit = {
        type = currentOutfit.type,
        head = sourceOutfit.head or 0,
        body = sourceOutfit.body or 0,
        legs = sourceOutfit.legs or 0,
        feet = sourceOutfit.feet or 0,
        addons = currentOutfit.addons or 0
    }
    
    -- Preserve current mount
    if currentOutfit.mount then
        outfit.mount = currentOutfit.mount
    end
    
    return outfit
end

-- Apply outfit to local player with validation
local function applyOutfit(outfit, targetName, isColorsOnly)
    if not outfit then return false end
    
    local player = g_game.getLocalPlayer()
    if not player then return false end
    
    -- Store current outfit to check if change was successful
    local oldOutfit = player:getOutfit()
    
    -- Apply the outfit
    setOutfit(outfit)
    
    -- Schedule a check to see if the outfit was applied
    schedule(200, function()
        local currentOutfit = player:getOutfit()
        if currentOutfit then
            local success = false
            
            if isColorsOnly then
                -- For colors only, check if colors match
                success = (currentOutfit.head == outfit.head and 
                          currentOutfit.body == outfit.body and 
                          currentOutfit.legs == outfit.legs and 
                          currentOutfit.feet == outfit.feet)
            else
                -- For full clone, check if type matches (if we tried to change it)
                if outfit.type and currentOutfit.type ~= outfit.type then
                    -- Outfit type didn't change - player doesn't have this outfit
                    modules.game_textmessage.displayFailureMessage("You don't have this outfit!")
                    warn("[Outfit Cloner] You don't have the outfit from " .. (targetName or "player"))
                    return
                end
                success = true
            end
            
            if success then
                if isColorsOnly then
                    modules.game_textmessage.displayStatusMessage("Colors copied from " .. (targetName or "player"))
                else
                    modules.game_textmessage.displayStatusMessage("Outfit cloned from " .. (targetName or "player"))
                end
            end
        end
    end)
    
    return true
end

-- ============================================================================
-- MENU ACTION HANDLERS
-- ============================================================================

-- Clone full outfit from target creature
local function cloneOutfitAction(menuPosition, lookThing, useThing, creatureThing)
    if not creatureThing then return end
    if not creatureThing:isPlayer() then return end
    
    local sourceOutfit = creatureThing:getOutfit()
    local newOutfit = buildFullOutfit(sourceOutfit)
    local name = creatureThing:getName() or "player"
    
    applyOutfit(newOutfit, name, false)
end

-- Copy only colors from target creature
local function copyColorsAction(menuPosition, lookThing, useThing, creatureThing)
    if not creatureThing then return end
    if not creatureThing:isPlayer() then return end
    
    local sourceOutfit = creatureThing:getOutfit()
    local newOutfit = buildColorsOnlyOutfit(sourceOutfit)
    local name = creatureThing:getName() or "player"
    
    applyOutfit(newOutfit, name, true)
end

-- ============================================================================
-- MENU CONDITION (when to show the options)
-- ============================================================================

-- Only show for other players (not self, not NPCs, not monsters)
local function isValidPlayerTarget(menuPosition, lookThing, useThing, creatureThing)
    if not creatureThing then return false end
    if not creatureThing:isPlayer() then return false end
    if creatureThing:isLocalPlayer() then return false end
    return true
end

-- ============================================================================
-- HOOK INTO GAME INTERFACE MENU
-- ============================================================================

local function registerMenuOptions()
    local gameInterface = modules.game_interface
    if not gameInterface then
        warn("[Outfit Cloner] game_interface module not found")
        return false
    end
    
    -- Initialize hookedMenuOptions if not exists
    if not gameInterface.hookedMenuOptions then
        gameInterface.hookedMenuOptions = {}
    end
    
    -- Create outfit category
    local categoryName = "OutfitCloner"
    if not gameInterface.hookedMenuOptions[categoryName] then
        gameInterface.hookedMenuOptions[categoryName] = {}
    end
    
    -- Register Clone Outfit option
    gameInterface.hookedMenuOptions[categoryName]["Clone Outfit"] = {
        condition = isValidPlayerTarget,
        callback = cloneOutfitAction,
        shortcut = nil
    }
    
    -- Register Copy Colors option
    gameInterface.hookedMenuOptions[categoryName]["Copy Colors"] = {
        condition = isValidPlayerTarget,
        callback = copyColorsAction,
        shortcut = nil
    }
    
    return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Register menu options on load
registerMenuOptions()
