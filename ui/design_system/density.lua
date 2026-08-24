--[[
  Density — token-driven UI density. All component sizing resolves through a
  density preset; no duplicated per-screen layouts.
]]

local presets = {
  default = {
    rowHeight = 22,
    controlHeight = 20,
    sidebarItemHeight = 26,
    padding = { 2, 4, 6, 8 },
    sectionGap = 8,
  },
  compact = {
    rowHeight = 18,
    controlHeight = 18,
    sidebarItemHeight = 22,
    padding = { 1, 3, 4, 6 },
    sectionGap = 6,
  },
  comfortable = {
    rowHeight = 26,
    controlHeight = 24,
    sidebarItemHeight = 30,
    padding = { 4, 6, 8, 12 },
    sectionGap = 12,
  },
}

local Density = {}

function Density.get(name)
  local preset = presets[name]
  if not preset then
    return setmetatable({ _fallback = "default" }, { __index = presets.default })
  end
  return preset
end

Density.presets = presets

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Density = Density
  nExBot.UI["ui.design_system.density"] = Density
end

return Density
