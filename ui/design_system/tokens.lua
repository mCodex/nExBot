--[[
  DesignTokens — the single source of semantic design values for the nExBot UI.

  No production screen/component hard-codes colors, margins, or radii. They all
  resolve through this token table. The table is frozen at load time so no
  module can silently mutate shared tokens.
]]

local version = 1

local colors = {
  background = {
    canvas       = "#191b1d",
    base         = "#242729",
    elevated     = "#303438",
    interactive  = "#3b4145",
    selected     = "#4a4333",
    card         = "#2a2d2f",
  },
  border = {
    subtle  = "#454b4f",
    default = "#626a6f",
    strong  = "#b6904d",
    accent  = "#b6904d",
  },
  text = {
    primary   = "#f4ead2",
    secondary = "#d7c8a5",
    muted     = "#b3aa96",
  },
  accent = {
    primary = "#f2c66d",
    hover   = "#ffda85",
  },
  toggle = {
    track    = "#3a3d40",
    trackOn  = "#2d4a3a",
  },
  success = "#91d982",
  warning = "#f2c66d",
  danger  = "#ff8f85",
  info    = "#9fd3df",
  active  = "#91d982",
  paused  = "#f2c66d",
  disabled = "#c0c7ca",
  degraded = "#e4ad75",
}

local spacing = { 2, 4, 6, 8, 12, 16, 20, 24 }

local radii = { sm = 2, md = 4, lg = 6 }
local borders = { subtle = 1, default = 1, strong = 2 }
local dimensions = {
  footerHeight = 32,
  minWidth = 320,
  minHeight = 240,
  maxWidth = 1200,
  maxHeight = 900,
}

local function sp(step)
  return spacing[step] or step
end

-- Frozen proxy: reads resolve to the backing store, every write errors.
local function freezeProxy(raw)
  local proxy = {}
  local mt = {
    __index = function(_, key)
      local v = raw[key]
      if v == nil then
        error("DesignTokens is frozen: unknown token requested: " .. tostring(key))
      end
      if type(v) == "table" then
        v = freezeProxy(v)
      end
      return v
    end,
    __newindex = function()
      error("DesignTokens is frozen: mutation is forbidden")
    end,
    __tostring = function() return "DesignTokens" end,
  }
  setmetatable(proxy, mt)
  return proxy
end

local tokens = freezeProxy({
  version = version,
  colors = colors,
  spacing = spacing,
  radii = radii,
  borders = borders,
  dimensions = dimensions,
  sp = sp,
})

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Tokens = tokens
  nExBot.UI["ui.design_system.tokens"] = tokens
end

return tokens
