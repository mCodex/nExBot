modules.game_interface.gameRootPanel.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == 2 then
        local child = rootWidget:recursiveGetChildByPos(mousePos)
        if child == widget then
            local function navigate(pageId)
                local ShellModule = nExBot and nExBot.UI and nExBot.UI.Shell
                local shell = ShellModule and ShellModule.instance and ShellModule.instance()
                if shell and shell.select then shell:select(pageId) end
            end
            local menu = g_ui.createWidget('PopupMenu')
            menu:setId("blzMenu")
            menu:setGameMenu(true)
            menu:addOption('AttackBot', function() navigate("attack") end, "OTCv8")
            menu:addOption('HealBot', function() navigate("healing") end, "OTCv8")
            menu:addOption('Conditions', function() navigate("conditions") end, "OTCv8")
            menu:addSeparator()
            menu:addOption('CaveBot', function() 
                if CaveBot.isOn() then 
                    CaveBot.setOff() 
                else 
                    CaveBot.setOn() 
                end 
            end, CaveBot.isOn() and "ON " or "OFF ")
            menu:addOption('TargetBot', function() 
                if TargetBot.isOn() then 
                    TargetBot.setOff() 
                else 
                    TargetBot.setOn(true, true)  -- force=true for user-initiated toggle
                end 
            end, TargetBot.isOn() and "ON " or "OFF ")
            menu:display(mousePos)
            return true
        end
    end
end