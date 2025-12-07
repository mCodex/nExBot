CaveBot.Extensions.Lure = {}

CaveBot.Extensions.Lure.setup = function()
  -- This action toggles TargetBot on/off for pulling/luring scenarios
  -- Renamed internally but kept for backward compatibility with existing configs
  CaveBot.registerAction("lure", "#FF0090", function(value, retries)
    value = value:lower()
    if value == "start" then
        TargetBot.setOff()
    elseif value == "stop" then
        TargetBot.setOn()
    elseif value == "toggle" then
      if TargetBot.isOn() then
        TargetBot.setOff()
      else
        TargetBot.setOn()
      end
    else
      warn("incorrect lure value! Use: start, stop, or toggle")
    end
    return true
  end)

  CaveBot.Editor.registerAction("lure", "lure", {
    value="toggle",
    title="Toggle TargetBot",
    description="Controls TargetBot state:\n- start: Turn TargetBot OFF (for luring)\n- stop: Turn TargetBot ON (resume attacking)\n- toggle: Switch between states",
    multiline=false,
    validation=[[(start|stop|toggle)$]]
  })
end