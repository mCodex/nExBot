-- Run inside OTClient after loading the bot's OTUI and the client styles.
local function checkOptions(dropdown)
  dropdown:onMousePress(dropdown:getPosition(), MouseLeftButton)
  local menu = rootWidget:getChildById(dropdown:getId() .. "PopupMenu")
  local rows = (menu.scrollArea or menu):getChildren()
  assert(#rows == #dropdown.options and #rows > 0)
  for _, row in ipairs(rows) do
    assert(row:getTextSize().width + 5 <= row:getWidth(), row:getText() .. " is clipped in the menu")
  end
  if not menu.scrollArea then
    for _, row in ipairs(rows) do
      assert(row:getTextSize().width <= dropdown.caption:getWidth(), row:getText() .. " is clipped in the field")
    end
  end
  local last = rows[#rows]
  local text = last:getText()
  last:onClick()
  assert(dropdown:getCurrentOption().text == text and dropdown.caption:getText() == text)
  assert(dropdown.caption:getX() >= dropdown:getX())
  assert(dropdown.caption:getX() + dropdown.caption:getWidth() <= dropdown:getX() + dropdown:getWidth() - 20)
end

return function(parent)
  local conditions = g_ui.createWidget("ConditionsWindow", parent)
  local recovery = conditions.Hold.UturaType
  recovery:setCurrentOption("Utura Gran")
  assert(recovery:getCurrentOption().text == "Utura Gran")
  assert(recovery:getTextOffset().x >= 0, "Recovery draws its selection outside the field")
  assert(recovery.caption:getText() == "Utura Gran")
  checkOptions(recovery)
  conditions:hide()
  local combo = g_ui.createWidget("ComboWindow", parent)
  checkOptions(combo.actions.followLeader)
  checkOptions(combo.actions.attackLeaderTarget)
  combo:hide()
  local equip = g_ui.createWidget("EquipWindow", parent)
  checkOptions(equip.inputPanel.useSecondCondition)
  equip:hide()

  local equipRow = g_ui.createWidget("TwoItemsAndSlotPanel", parent)
  equipRow.slot:setCurrentIndex(9)
  local selectedSlot
  equipRow.slot.onOptionChange = function() selectedSlot = equipRow.slot.currentIndex end
  local slot = g_ui.createWidget("NexBotDropdown", equipRow)
  slot:replaceClientDropdown(equipRow.slot)
  assert(equipRow.slot == slot and slot.caption:getText() == "Finger")
  slot:setCurrentOption("Ammo")
  assert(selectedSlot == 10)
  equipRow:hide()

  local window = g_ui.createWidget("HealWindow", parent)
  for _, form in ipairs({window.healer.spells, window.healer.items}) do
    local source = form.source
    local comparison = form.comparison
    checkOptions(source)
    checkOptions(comparison)
    assert(comparison:getY() >= source:getY() + source:getHeight() + 2, "Healing fields touch")
  end
  window:hide()

  local context = {storage = {}, configDir = "", error = error}
  local configModule = assert(loadstring(g_resources.readFileContents("/game_bot/functions/config.lua")))
  setfenv(configModule, setmetatable({G = {botContext = context}}, {__index = _G}))()
  for _, profile in ipairs({{"cavebot_configs", "cfg"}, {"targetbot_configs", "json"}}) do
    local selector = g_ui.createWidget("NexBotProfileSelector", parent)
    selector:setWidth(150)
    local config = context.Config.setup(profile[1], selector, profile[2], function() end)
    checkOptions(selector.list)
    assert(config.getActiveConfigName() == selector.list:getCurrentOption().text)
    selector:hide()
  end

  local friend = g_ui.createWidget("FriendHealer", parent)
  local box = friend.conditions.box
  for _, setting in ipairs({"Mana Item", "Item Range: 10", "Health Item", "Mas Res Players: 10",
      "Heal Friend at: 100%", "Use Gran Sio at: 100%", "Use Tio Sio at: 100%",
      "Min Player HP%: 100%", "Min Player MP%: 100%"}) do
    local kind = setting:find("Item$") and "HealItem" or "HealScroll"
    local cell = g_ui.createWidget(kind, box)
    cell.text:setText(setting)
    assert(cell.text:getTextSize().width <= cell.text:getWidth(), setting .. " is clipped")
    assert(cell:getY() + cell:getHeight() <= box:getY() + box:getHeight(), setting .. " is below the grid")
  end
  local entry = g_ui.createWidget("PriorityEntry", friend.priority.list)
  entry.caption:setText("Exura Gran Mas Res")
  assert(entry.caption:getTextSize().width <= entry.caption:getWidth())
  assert(entry.caption:getX() + entry.caption:getWidth() <= entry.decrement:getX())
  friend:hide()
  dofile("/tests/ui/container_titles.lua")(parent)
end
