local M = {}

function M.convertSpellsToEngineFormat(spellTable)
  if not spellTable then return {} end
  local converted = {}
  for _, spell in ipairs(spellTable) do
    local valid = true
    if spell.enabled == false or not spell.spell or spell.spell == "" then
      valid = false
    end

    local hp, mp = nil, nil
    local isBelow = spell.sign == "<" or spell.sign == nil
    if spell.origin == "HP" or spell.origin == "HP%" then
      if isBelow then
        hp = spell.value or 50
      else
        valid = false
      end
    elseif spell.origin == "MP" or spell.origin == "MP%" then
      if isBelow then
        mp = spell.value or 50
      else
        valid = false
      end
    else
      valid = false
    end

    if not hp and not mp then
      valid = false
    end

    if valid then
      table.insert(converted, {
        name = spell.spell,
        key = (spell.spell or ""):lower(),
        hp = hp,
        mp = mp,
        op = spell.sign or "<",
        mana = spell.cost or spell.mana or 0,
        cd = 1100,
        prio = #converted + 1
      })
    end
  end
  return converted
end

function M.convertPotionsToEngineFormat(itemTable, getItemNameFn)
  if not itemTable then return {} end
  local converted = {}
  for _, item in ipairs(itemTable) do
    if item.enabled ~= false and item.item and item.item > 0 then
      local hp, mp = nil, nil
      local isBelow = item.sign == "<" or item.sign == nil

      if item.origin == "HP" or item.origin == "HP%" then
        if isBelow then
          hp = item.value or 50
        end
      elseif item.origin == "MP" or item.origin == "MP%" then
        if isBelow then
          mp = item.value or 50
        end
      end

      local itemName = nil
      if getItemNameFn then
        itemName = getItemNameFn(item.item)
      end
      if not itemName then
        itemName = "potion #" .. item.item
      end

      if hp or mp then
        table.insert(converted, {
          id = item.item,
          key = "potion_" .. item.item,
          hp = hp,
          mp = mp,
          cd = 1000,
          prio = #converted + 1,
          name = itemName
        })
      end
    end
  end
  return converted
end

SpellResolver = M
return M
