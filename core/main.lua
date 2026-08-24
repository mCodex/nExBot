-- nExBot v5 — the left bot bar is replaced by the BotShell, which auto-attaches
-- at startup (see ui/init.lua). This block is kept only as a minimal fallback.

local version = nExBot.version or "0.0.0"

UI.Label("nExBot v" .. version)
UI.Separator()
