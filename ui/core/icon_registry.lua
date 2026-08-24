--[[
  IconRegistry — O(1) icon lookup with safe fallback.

  All modules resolve icons through this registry. No hard-coded icon paths
  inside screens. The raster path may be a format string with one %d (size),
  matching the build pipeline output: <name>_<size>.png.
]]

local IconRegistry = {}
local icons = {}
local count = 0

local FALLBACK_SVG = "ui/assets/icons/warning.svg"
local FALLBACK = {
  id = "fallback",
  svg = FALLBACK_SVG,
  raster = "ui/assets/icons/generated/warning_%d.png",
}

function IconRegistry.register(id, desc)
  if type(id) ~= "string" or id == "" then return false end
  if type(desc) ~= "table" or type(desc.svg) ~= "string" then return false end
  if icons[id] then return false end
  icons[id] = {
    id = id,
    svg = desc.svg,
    raster = desc.raster,
  }
  count = count + 1
  return true
end

function IconRegistry.get(id)
  return icons[id] or FALLBACK
end

function IconRegistry.has(id)
  return icons[id] ~= nil
end

function IconRegistry.resolve(id, size)
  local icon = icons[id]
  if not icon then return FALLBACK.svg end
  if icon.raster then
    return icon.raster:gsub("%%d", tostring(size))
  end
  return icon.svg
end

function IconRegistry.count()
  return count
end

function IconRegistry.reset()
  icons = {}
  count = 0
end

-- Bulk register a list of { id = name, svg = path, raster = formatString }.
function IconRegistry.registerAll(list)
  local n = 0
  for _, item in ipairs(list) do
    if IconRegistry.register(item.id, item) then n = n + 1 end
  end
  return n
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.IconRegistry = IconRegistry
end

return IconRegistry
