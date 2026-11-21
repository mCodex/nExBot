-- Pure action-type -> Tibia sprite mapping for the waypoint editor's row
-- icons and add-action palette. No g_ui dependency.
--
-- Only maps action types where the item id is either parsed directly out of
-- the waypoint's own value (usewith, use-with-item-id) or already verified
-- in-repo (goto/gotolabel/label, follow reuse the cockpit's own sprites, see
-- ui/modules/cockpit.lua). Every other action type returns nil rather than
-- guess at an unverified item id - callers fall back to a placeholder.
local Icons = {}

local STATIC_ICONS = {
  ["goto"] = 3003,
  gotolabel = 3003,
  label = 3003,
  follow = 3155,
}

local function parseLeadingItemId(value)
  if type(value) ~= "string" then return nil end
  local id = value:match("^%s*(%d+)%s*,")
  if not id then
    id = value:match("^%s*(%d+)%s*$")
  end
  return id and tonumber(id) or nil
end

function Icons.iconFor(action, value)
  if type(action) ~= "string" then return nil end

  if action == "usewith" then
    return parseLeadingItemId(value)
  end

  if action == "use" then
    -- A bare number is an inventory item id; a comma-separated value is a
    -- position (x,y,z), which has no representative item sprite.
    if type(value) == "string" and value:match("^%s*%d+%s*$") then
      return tonumber(value)
    end
    return nil
  end

  return STATIC_ICONS[action]
end

if nExBot then
  nExBot.Nav = nExBot.Nav or {}
  nExBot.Nav["cavebot.editor_icons"] = Icons
end

return Icons
