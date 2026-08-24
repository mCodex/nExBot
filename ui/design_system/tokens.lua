--[[
  DesignTokens — the single source of semantic design values for the nExBot UI.

  No production screen/component hard-codes colors, margins, or radii. They all
  resolve through this token table. The table is frozen at load time so no
  module can silently mutate shared tokens.
]]

local version = 1

local colors = {
  background = {
    canvas       = "#20201e",
    base         = "#292927",
    elevated     = "#333331",
    interactive  = "#3b3b39",
    selected     = "#4a4538",
  },
  border = {
    subtle  = "#383836",
    default = "#4a4a47",
    strong  = "#6b5b35",
  },
  text = {
    primary   = "#d8c89c",
    secondary = "#b8aa82",
    muted     = "#81785f",
  },
  accent = {
    primary = "#c49a4a",
    hover   = "#d4ad61",
  },
  success = "#6fa85a",
  warning = "#c49a4a",
  danger  = "#c45b4d",
  info    = "#8ea7a0",
  active  = "#6fa85a",
  paused  = "#c49a4a",
  disabled = "#686657",
  degraded = "#aa7f58",
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
