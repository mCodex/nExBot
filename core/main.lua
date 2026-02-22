local version = nExBot.version or "0.0.0"

local getClient = nExBot.Shared.getClient

UI.Label("nExBot v" .. version)

local discordBtn = UI.Button("Join our Discord", function()
  g_platform.openUrl("https://discord.gg/qKasgMN7gG")
end)
if discordBtn then
  discordBtn:setTooltip("Join the nExBot Discord community for help, updates, and configs.")
end

UI.Separator()