-- Drive the same Reopen All button that the sidebar binds, with delayed server replies.
local function bag(id, pages)
  return {getId = function() return id end, isContainer = function() return true end, pages = pages or {{}}}
end

local function client(root, options)
  options = options or {}
  local timers, windows, requests, opened, warnings = {}, {}, {}, {}, {}
  local clock, complete, inFlight = 0, 0, false
  local openEvent, closeEvent, addEvent, updateEvent, sortTick
  local sidebar = {}
  local noop = function() end
  local function schedule(ms, fn)
    timers[#timers + 1] = {at = clock + ms, fn = fn}
  end
  local function widget()
    return setmetatable({}, {__index = function() return noop end})
  end
  for _, id in ipairs({"setupBtn", "openAll", "closeAll", "reopenAll", "maximizeAll",
                       "minimizeAll", "purseSwitch", "autoMinSwitch"}) do sidebar[id] = widget() end
  sidebar.setId = noop
  local function window(id, item, page)
    local capacity = #item.pages[1]
    local items = item.pages[page]
    return {
      getId = function() return id end, getName = function() return item.name or "Backpack" end,
      getContainerItem = function() return item end, getItems = function() return items end,
      getItem = function(_, slot) return items[slot + 1] end,
      getFirstIndex = function() return (page - 1) * capacity end,
      hasPages = function() return #item.pages > 1 end, getCapacity = function() return capacity end,
      getSize = function() return (#item.pages - 1) * capacity + #item.pages[#item.pages] end,
    }
  end
  if options.previous then windows[0] = window(0, options.previous, 1) end
  for id, item in ipairs(options.openBags or {}) do windows[id] = window(id, item, 1) end
  local game = {
    move = options.move,
    getContainers = function() return windows end,
    getContainer = function(id) return windows[id] end,
    getLocalPlayer = function()
      if options.equipped then return {getInventoryItem = function(_, slot)
        if options.v8 then assert(slot >= 1 and slot <= 10) end
        return options.equipped[slot]
      end} end
    end,
    close = function(c)
      schedule(650, function()
        windows[c:getId()] = nil
        closeEvent(c)
      end)
    end,
    open = function(item)
      assert(not inFlight, "two simultaneous opens compete for the same window")
      if options.previous then assert(clock >= 650, "open sent before the old window closed") end
      local id = 0
      while windows[id] do id = id + 1 end
      requests[#requests + 1] = item
      if options.drop == item then
        if not options.permanent then options.drop = nil end
        return id
      end
      inFlight = true
      schedule(45, function()
        if options.unrelated == item then
          local other = window(id + 20, bag(item:getId()), 1)
          windows[id + 20] = other
          openEvent(other)
          options.unrelated = nil
        end
        inFlight = false
        local c = window(id, item, 1)
        windows[id] = c
        opened[#opened + 1] = item
        openEvent(c)
        if options.afterOpen then options.afterOpen(item, c, addEvent, updateEvent) end
      end)
      return id
    end,
    seekInContainer = function(id, index)
      assert(not inFlight)
      if options.dropPage == index then return end
      inFlight = true
      schedule(80, function()
        inFlight = false
        local old = windows[id]
        local c = window(id, old:getContainerItem(), 1 + index / old:getCapacity())
        windows[id] = c
        openEvent(c, old)
        closeEvent(old)
      end)
    end,
  }
  local env = setmetatable({
    nExBot = {isOpenTibiaBR = not options.v8, paths = {core = "core"}, Shared = {deepClone = function(v) return v end, getClient = noop}},
    nExBotRuntime = options.runtime,
    storage = {containerPanel = {autoMinimize = false, purse = options.purse ~= nil and not options.skipPurse, containerList = options.rules or {}, sortEnabled = options.rules ~= nil}},
    RustBridge = {observeReopen = options.observeReopen},
    g_game = game, g_clock = {millis = function() return clock end},
    getBack = function() return root end, getPurse = function() return options.purse end,
    UI = {Separator = noop, createWidget = function() return sidebar end},
    EventBus = {emit = function(name)
      if name == "containers:open_all_complete" then complete = complete + 1 end
    end},
    schedule = schedule, macro = function(_, fn) sortTick = fn end, setDefaultTab = noop,
    getContainerByItem = options.findContainer,
    onContainerOpen = function(fn) openEvent = fn end, onContainerClose = function(fn) closeEvent = fn end,
    onContainerUpdateItem = function(fn) updateEvent = fn end,
    onAddItem = function(fn) addEvent = fn end, onRemoveItem = noop, onPlayerInventoryChange = noop,
    onPlayerHealthChange = noop, warn = function(msg) warnings[#warnings + 1] = msg end,
  }, {__index = _G})
  env.g_resources = {readFileContents = function(path)
    local file = assert(io.open(path))
    local source = file:read("*a")
    file:close()
    return source
  end}
  env.load = function(source, path)
    if setfenv then return setfenv(assert(loadstring(source, path)), env) end
    return assert(load(source, path, "t", env))
  end
  env.load(env.g_resources.readFileContents("core/Containers.lua"), "Containers.lua")()
  local function run()
    local steps = 0
    while #timers > 0 do
      local first = 1
      for i = 2, #timers do if timers[i].at < timers[first].at then first = i end end
      local timer = table.remove(timers, first)
      clock = timer.at
      timer.fn()
      steps = steps + 1
      assert(steps < 2000, "reopen did not finish")
    end
    return complete
  end
  return sidebar, run, requests, opened, warnings, sortTick
end

describe("Reopen All", function()
  it("opens bags on equipped slots, including extended slots when the back slot is empty", function()
    local pouch, left, right, extra, other, deep = bag(23396), bag(2866), bag(2866), bag(2866), bag(2866), bag(5000)
    extra.pages = {{deep}}
    local ui, run, _, opened = client(nil, {
      equipped = {[5] = right, [6] = left, [11] = pouch, [12] = extra, [15] = other}, purse = pouch, skipPurse = true,
    })
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({right, left, extra, other, deep}, opened)
  end)

  it("uses only standard slots and the dedicated purse accessor on OTCv8", function()
    local ammo, purse = bag(2866), bag(23396)
    local ui, run, _, opened = client(nil, {equipped = {[10] = ammo}, purse = purse, v8 = true})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({purse, ammo}, opened)
  end)

  it("traverses bags with excluded words in their names and the enabled store inbox, skipping actual excluded containers", function()
    local root, supplies, purse, quiver = bag(2854), bag(3000), bag(23396), bag(35847)
    local a, b, hidden = bag(101), bag(102), bag(103)
    supplies.name, supplies.pages = "Deadeye Backpack", {{a}}
    purse.name, purse.pages = "Store Inbox", {{b}}
    quiver.name, quiver.pages = "Jungle Quiver", {{hidden}}
    root.pages = {{supplies, quiver}}
    local ui, run, _, opened = client(root, {purse = purse})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({root, purse, supplies, quiver, b, a}, opened)
  end)

  it("follows a refreshed bag handle and discovers a bag created by slot update", function()
    local old, refreshed, sibling, created, child = bag(2866), bag(2866), bag(2866), bag(2866), bag(111)
    local ordinary = {isContainer = function() return false end}
    refreshed.pages = {{child}}
    local root = bag(2854, {{old, sibling, ordinary}})
    local ui, run, _, opened = client(root, {afterOpen = function(item, c, _, update)
      if item ~= root then return end
      root.pages[1][1], root.pages[1][3] = refreshed, created
      if update then update(c, 0, refreshed, old); update(c, 2, created, ordinary) end
    end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({root, refreshed, sibling, created, child}, opened)
  end)

  it("sends constant-size page membership and falls back when the native binding does not support it", function()
    local child = bag(2866)
    local root = bag(2854, {{{isContainer = function() return false end}}, {child}})
    for _, supported in ipairs({true, false}) do
      local frames = {}
      local ui, run, _, opened = client(root, {runtime = {decide = function(op, request)
        if op ~= "reopen_page" then return end
        frames[#frames + 1] = request
        if supported then return request.page == 0 and {page = 1} or {} end
      end}})
      ui.reopenAll:onClick()
      assert.equals(1, run())
      assert.same({root, child}, opened)
      assert.same({page = 0, capacity = 1, size = 2, first_visited = true, continuation_visited = false}, frames[1])
    end
  end)

  it("recognizes equivalent client handles delivered again for the same bag", function()
    local original = bag(2866)
    local metatable = {__eq = function(a, b) return a.nativeId == b.nativeId end}
    original.nativeId = 42
    setmetatable(original, metatable)
    local alias = setmetatable({nativeId = 42, getId = original.getId, isContainer = original.isContainer,
      pages = original.pages}, metatable)
    local root = bag(2854, {{original}})
    local ui, run, requests = client(root, {afterOpen = function(item, c, add)
      if item == root then add(c, 0, alias) end
    end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.equals(2, #requests)
  end)

  it("does not reopen an acknowledged bag on a same-slot, same-type refresh", function()
    local first, refresh = bag(2866), bag(2866)
    local root = bag(2854, {{first}})
    local parent
    local ui, run, requests = client(root, {afterOpen = function(item, c, _, update)
      if item == root then parent = c end
      if item ~= first then return end
      root.pages[1][1] = refresh
      update(parent, 0, refresh, first)
    end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({root, first}, requests)
  end)

  it("uses the replacement bag when its type changes before the queued open", function()
    local first, replacement = bag(2866), bag(3003)
    local root = bag(2854, {{first}})
    local ui, run, requests = client(root, {afterOpen = function(item, c, _, update)
      if item ~= root then return end
      root.pages[1][1] = replacement
      update(c, 0, replacement, first)
    end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({root, replacement}, requests)
  end)

  it("reports an unacknowledged later page as incomplete", function()
    local child = bag(2866)
    local root = bag(2854, {{{isContainer = function() return false end}}, {child}})
    local summary
    local ui, run, _, opened, warnings = client(root, {
      dropPage = 1, observeReopen = function(metrics) summary = metrics end,
    })
    ui.reopenAll:onClick()
    assert.equals(0, run())
    assert.same({root}, opened)
    assert.equals(2, summary.timeouts)
    assert.equals(1, #warnings)
  end)

  it("drains the old windows, then opens identical siblings, deep bags and the purse exactly once", function()
    local leaf, otherLeaf = bag(3003), bag(3003)
    local left, right = bag(2866, {{leaf}}), bag(2866, {{otherLeaf}})
    local root, purse = bag(2854, {{left, right}}), bag(23396)
    local ui, run, requests, opened = client(root, {previous = bag(2854), purse = purse, unrelated = left})
    ui.reopenAll:onClick()
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.same({root, purse, left, right, leaf, otherLeaf}, opened)
    assert.equals(6, #requests)
    for i, item in ipairs({root, purse, left, right, leaf, otherLeaf}) do assert.equals(item, opened[i]) end
  end)

  it("opens children on later pages even when the first page has no bags", function()
    local ordinary = {isContainer = function() return false end}
    local a, b = bag(2866), bag(2866)
    local root = bag(2854, {{ordinary}, {a}, {b}})
    local ui, run, requests = client(root)
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.equals(a, requests[2])
    assert.equals(b, requests[3])
    assert.equals(3, #requests)
  end)

  it("handles shifted slots and a new bag without reopening an identical sibling", function()
    local a, b, inserted = bag(2866), bag(2866), bag(2866)
    local root = bag(2854, {{a, b}})
    local ui, run, _, opened = client(root, {afterOpen = function(item, c, add)
      if item == root then
        table.insert(root.pages[1], 1, inserted)
        add(c, 0, inserted)
      end
    end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.equals(4, #opened)
    assert.equals(a, opened[2])
    assert.equals(b, opened[3])
    assert.equals(inserted, opened[4])
  end)

  it("retries a lost open and reports a partial result after a repeated refusal", function()
    for _, permanent in ipairs({false, true}) do
      local missing, sibling = bag(2866), bag(2866)
      local ui, run, requests, _, warnings = client(bag(2854, {{missing, sibling}}),
        {drop = missing, permanent = permanent})
      ui.reopenAll:onClick()
      assert.equals(permanent and 0 or 1, run())
      assert.equals(4, #requests)
      assert.equals(missing, requests[3])
      assert.equals(sibling, requests[4])
      assert.equals(permanent and 1 or 0, #warnings)
    end
  end)

  it("reports request latency separately from retries and pacing", function()
    local leaf = bag(2866)
    local root = bag(2854, {{leaf}})
    local summary
    local ui, run = client(root, {drop = leaf, observeReopen = function(metrics) summary = metrics end})
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.equals(3, summary.requests)
    assert.equals(1, summary.timeouts)
    assert.equals(1, summary.samples)
    assert.equals(45, summary.ack_ms)
    assert.equals(45, summary.max_ack_ms)
    assert.is_true(summary.elapsed_ms >= 2200)
  end)

  it("does not stop at 19 open windows or 50 bags of the same type", function()
    local children = {}
    for i = 1, 51 do children[i] = bag(2866) end
    local ui, run, requests = client(bag(2854, {children}))
    ui.reopenAll:onClick()
    assert.equals(1, run())
    assert.equals(52, #requests)
  end)
end)

describe("Container Panel sorting", function()
  it("resolves an unavailable destination once and retains the first matching rule", function()
    local first = bag(4001)
    local second = bag(4002)
    local lookups = {}
    local _, _, _, _, _, tick = client(nil, {
      openBags = {bag(2854, {{first, second, first}})},
      rules = {
        {itemId = 2866, enabled = true, items = {{id = 4001}, 4002}},
        {itemId = 2867, enabled = true, items = {4001}},
      },
      findContainer = function(id) lookups[#lookups + 1] = id end,
      move = function() error("An unavailable destination must not move items") end,
    })
    tick({setOff = function() end})
    assert.same({2866}, lookups)
  end)
end)
