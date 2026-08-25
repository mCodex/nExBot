local Presenter = {}

local function readableOrigin(origin)
  return ({ HP = "HP", ["HP%"] = "HP", MP = "MP", ["MP%"] = "MP", burst = "Burst" })[origin] or tostring(origin or "Value")
end

function Presenter.healTrigger(rule)
  local suffix = tostring(rule.origin or ""):find("%", 1, true) and "%" or ""
  local parts = { readableOrigin(rule.origin) .. " " .. (rule.sign or "<") .. " " .. tostring(rule.value or 0) .. suffix }
  if rule.cost then parts[#parts + 1] = "Mana > " .. tostring(rule.cost) end
  return table.concat(parts, " · ")
end

function Presenter.attackTrigger(rule)
  local count = tostring(rule.count or 1) .. (rule.orMore and "+" or "") .. " creatures"
  local parts = { count }
  if rule.minHp ~= nil or rule.maxHp ~= nil then
    parts[#parts + 1] = "HP " .. tostring(rule.minHp or 0) .. "-" .. tostring(rule.maxHp or 100) .. "%"
  end
  if tonumber(rule.mana) and tonumber(rule.mana) > 0 then parts[#parts + 1] = "Mana > " .. tostring(rule.mana) end
  return table.concat(parts, " · ")
end

if nExBot then
  nExBot.UI = nExBot.UI or {}
  nExBot.UI.RulePresenter = Presenter
  nExBot.UI["ui.core.rule_presenter"] = Presenter
end

return Presenter
