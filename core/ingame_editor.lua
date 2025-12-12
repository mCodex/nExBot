setDefaultTab("Tools")
-- allows to test/edit bot lua scripts ingame
-- Scripts are saved to storage.ingame_hotkeys and executed on bot load

-- Function to execute ingame scripts safely
local function executeIngameScripts()
  local scripts = storage.ingame_hotkeys
  if type(scripts) == "string" and scripts:len() > 3 then
    local status, result = pcall(function()
      assert(load(scripts, "ingame_editor"))()
    end)
    if not status then 
      warn("[Ingame Editor] Error:\n" .. tostring(result))
      return false
    end
    return true
  end
  return false
end

UI.Button("Ingame script editor", function()
    UI.MultilineEditorWindow(storage.ingame_hotkeys or "", {title="Hotkeys editor", description="You can add your custom scripts here. Click Ok to save and reload bot."}, function(text)
      -- Store in global storage (automatically persisted by OTClient)
      storage.ingame_hotkeys = text
      
      -- Inform user
      info("[Ingame Editor] Script saved. Reloading bot...")
      
      -- Use a longer delay to ensure storage is written before reload
      schedule(500, function()
        -- reload() is a built-in OTClient function that reloads the bot
        -- Storage is automatically saved before reload
        reload()
      end)
    end)
  end)
  
  UI.Separator()
  
  -- Execute saved scripts on bot load
  if storage.ingame_hotkeys and type(storage.ingame_hotkeys) == "string" and #storage.ingame_hotkeys > 3 then
    local ok = executeIngameScripts()
    if ok then
      info("[Ingame Editor] Custom scripts loaded successfully")
    end
  end
  
  UI.Separator()