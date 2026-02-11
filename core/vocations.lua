local Vocations = {}

Vocations.IDS = {
  KNIGHT = {1, 11},
  PALADIN = {2, 12},
  SORCERER = {3, 13},
  DRUID = {4, 14},
  MONK = {5, 15}
}

local function matches(vocId, list)
  if not vocId or not list then return false end
  for i = 1, #list do
    if vocId == list[i] then
      return true
    end
  end
  return false
end

function Vocations.isKnight(vocId)
  return matches(vocId, Vocations.IDS.KNIGHT)
end

function Vocations.isPaladin(vocId)
  return matches(vocId, Vocations.IDS.PALADIN)
end

function Vocations.isSorcerer(vocId)
  return matches(vocId, Vocations.IDS.SORCERER)
end

function Vocations.isDruid(vocId)
  return matches(vocId, Vocations.IDS.DRUID)
end

function Vocations.isMonk(vocId)
  return matches(vocId, Vocations.IDS.MONK)
end

function Vocations.getShortName(vocId)
  if Vocations.isKnight(vocId) then return "EK" end
  if Vocations.isPaladin(vocId) then return "RP" end
  if Vocations.isSorcerer(vocId) then return "MS" end
  if Vocations.isDruid(vocId) then return "ED" end
  if Vocations.isMonk(vocId) then return "MN" end
  return ""
end

return Vocations
