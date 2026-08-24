--[[
  Typography — named styles resolved through a single approved font map.

  These are the ONLY font names the UI layer may use. The font engine workstream
  is out of scope; this maps named styles onto fonts already available in the
  client (OTBR/OTCv8 both ship verdana-11px-rounded, verdana-11px-monochrome,
  terminus-10px, cipsoftFont).
]]

local fonts = {
  ["verdana-11px-rounded"] = true,
  ["verdana-11px-monochrome"] = true,
  ["terminus-10px"] = true,
  ["cipsoftFont"] = true,
}

local styles = {
  displayMetric  = { font = "verdana-11px-rounded", size = 18 },
  windowTitle    = { font = "verdana-11px-rounded", size = 13 },
  moduleTitle    = { font = "verdana-11px-rounded", size = 13 },
  sectionTitle   = { font = "verdana-11px-rounded", size = 11 },
  body           = { font = "verdana-11px-rounded", size = 11 },
  rowTitle       = { font = "verdana-11px-rounded", size = 11 },
  helper         = { font = "verdana-11px-monochrome", size = 10 },
  metadata       = { font = "verdana-11px-monochrome", size = 10 },
  badge          = { font = "verdana-11px-rounded", size = 10 },
  mono           = { font = "terminus-10px", size = 10 },
}

local Typography = {}

function Typography.get(name)
  local style = styles[name]
  if not style then
    return setmetatable({ _fallback = "body" }, { __index = styles.body })
  end
  return style
end

Typography.styles = styles
Typography.fonts = fonts

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.Typography = Typography
  nExBot.UI["ui.design_system.typography"] = Typography
end

return Typography
