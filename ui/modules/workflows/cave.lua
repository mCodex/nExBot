-- Cave workflow controls: route profile, navigation toggles, waypoints.

local Components = nExBot and nExBot.UI and nExBot.UI["ui.components.components"]
local DataTable = nExBot and nExBot.UI and nExBot.UI.DataTable
local Shared = nExBot and nExBot.UI and nExBot.UI["ui.modules.workflows.shared"]

local CavePage = {}

function CavePage.render(content, shell)
  if not CaveBot then return end
  Components.sectionHeader(content, { title = "Route" })
  Shared.profileSelect(content, {
    id = "caveProfile",
    items = CaveBot.listProfiles and CaveBot.listProfiles() or {},
    value = CaveBot.getCurrentProfile and CaveBot.getCurrentProfile(),
    onChange = function(name)
      if CaveBot.setCurrentProfile then CaveBot.setCurrentProfile(name) end
      Shared.rerender(shell)
    end,
  })
  Shared.newProfileAction(content, {
    id = "newCaveProfile", text = "New Profile", shell = shell,
    prompt = { title = "New Cave Profile", label = "Enter a name for the new profile" },
    onCreate = function(name)
      if not CaveBot.createProfile then return false, "Not available" end
      return CaveBot.createProfile(name)
    end,
  })

  local config = CaveBot.Config
  if not config or not config.get or not config.set then return end
  Components.sectionHeader(content, { title = "Navigation" })
  for _, setting in ipairs({
    { "ignoreFields", "Ignore fields" },
    { "mapClick", "Map click" },
    { "autoUseTools", "Auto tools" },
    { "autoOpenDoors", "Auto doors" },
  }) do
    local key, label = setting[1], setting[2]
    Components.toggleRow(content, {
      id = "cave_" .. key,
      label = label,
      value = config.get(key),
      onChange = function(value) config.set(key, value) end,
    })
  end

  local route = CaveBot.Route
  if not route or not route.getChildren then return end
  local waypoints = route:getChildren()
  Components.sectionHeader(content, { title = "Waypoints" })
  Components.label(content, { text = string.format("%d waypoint(s) in this route", #waypoints), textStyle = "metadata" })
  if DataTable then
    local waypointRows = {}
    for index, widget in ipairs(waypoints) do
      local text = widget.getText and widget:getText() or tostring(widget.value or "Waypoint")
      waypointRows[#waypointRows + 1] = {
        id = widget.getId and widget:getId() or index,
        revision = tostring(index) .. ":" .. text,
        title = index .. "  " .. text,
        secondary = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "Selected" or "Pending",
        status = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "ACTIVE" or "INFO",
        statusText = index == (route.getFocusedChild and route:getChildIndex(route:getFocusedChild()) or -1) and "Selected" or "Pending",
        onClick = function() if route.focus then route:focus(widget) end end,
      }
    end
    DataTable.create(content, {
      id = "caveWaypoints", title = "Route", rows = waypointRows,
      rowKey = function(row) return row.id end, pageSize = Shared.PAGE_SIZE,
      emptyMessage = "No waypoints yet. Add the first route step.",
    })
  end

  local actions = Shared.actionBar(content)
  Shared.actionButton(actions, { id = "openWaypointEditor", text = "Open Waypoint Editor", onClick = function()
    if CaveBot.Editor and CaveBot.Editor.show then CaveBot.Editor.show() end
  end })
  if CaveBot.Recorder then
    local recording = CaveBot.Recorder.isOn and CaveBot.Recorder.isOn()
    Shared.actionButton(actions, {
      id = "recordRoute",
      text = recording and "Stop Recording" or "Record Route",
      variant = recording and "danger" or nil,
      onClick = function()
        if CaveBot.Recorder.isOn and CaveBot.Recorder.isOn() then
          CaveBot.Recorder.disable()
        else
          CaveBot.Recorder.enable()
        end
        Shared.rerender(shell)
      end,
    })
  end
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI["ui.modules.workflows.cave"] = CavePage
end

return CavePage
