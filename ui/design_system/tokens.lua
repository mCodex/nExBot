--[[
  DesignTokens — the single source of semantic design values for the nExBot UI.

  No production screen/component hard-codes colors, margins, or radii. They all
  resolve through this token table. The table is frozen at load time so no
  module can silently mutate shared tokens.
]]

local version = 1

local colors = {
  background = {
    canvas       = "#12141a",
    base         = "#1a1d26",
    elevated     = "#222634",
    interactive  = "#2a2f40",
    selected     = "#33405e",
  },
  border = {
    subtle  = "#2c3140",
    default = "#3a4154",
    strong  = "#4a5268",
  },
  text = {
    primary   = "#e8eaf0",
    secondary = "#b8bdc9",
    muted     = "#7a8092",
  },
  accent = {
    primary = "#4f9cf9",
    hover   = "#6fb0fb",
  },
  success = "#4ade80",
  warning = "#fbbf24",
  danger  = "#f87171",
  info    = "#38bdf8",
  active  = "#4ade80",
  paused  = "#fbbf24",
  disabled = "#5a5f6e",
  degraded = "#c084fc",
}

local spacing = { 2, 4, 6, 8, 12, 16, 20, 24 }

local radii = { sm = 2, md = 4, lg = 6 }
local borders = { subtle = 1, default = 1, strong = 2 }
local dimensions = {
  sidebarWidth = 176,
  headerHeight = 40,
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
end

return tokens
