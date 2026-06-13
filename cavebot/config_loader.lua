-- config_loader.lua
-- Utilities to load and inspect cfg text using the v2 route pipeline.

CaveBot = CaveBot or {}

local ConfigLoader = {}

local function trim(s)
  if not s then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function ConfigLoader.parseText(cfgText)
  local nodes = {}
  if type(cfgText) ~= "string" then
    return nodes
  end

  local idx = 0
  for line in cfgText:gmatch("[^\r\n]+") do
    local raw = trim(line)
    if raw ~= "" and not raw:match("^config:%s*") and not raw:match("^extensions:%s*") then
      idx = idx + 1
      local WaypointSchema = CaveBot.WaypointSchema
      local parsed = WaypointSchema and WaypointSchema.parseLine and WaypointSchema.parseLine(raw, idx) or nil
      if parsed then
        nodes[#nodes + 1] = parsed
      end
    end
  end

  return nodes
end

function ConfigLoader.loadFromText(cfgText)
  local nodes = ConfigLoader.parseText(cfgText)
  local RouteCompiler = CaveBot.RouteCompiler
  local RouteValidator = CaveBot.RouteValidator
  local route = RouteCompiler and RouteCompiler.compile and RouteCompiler.compile(nodes) or nil
  local report = RouteValidator and RouteValidator.validate and RouteValidator.validate(route) or nil

  return {
    nodes = nodes,
    route = route,
    report = report,
  }
end

CaveBot.ConfigLoader = ConfigLoader
return ConfigLoader
