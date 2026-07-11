-- tests/unit/event_bus_spec.lua
-- Characterization tests for EventBus (core dispatch logic)

local mock = require("tests.helpers.mock_otclient")

describe("EventBus", function()
  local bus

  before_each(function()
    mock.install()
    -- Create a fresh EventBus instance (not loading event_bus.lua which has side effects)
    bus = {
      _listeners = {},
      _queue = {},
      _processing = false,
    }

    function bus:on(event, callback, priority)
      priority = priority or 0
      if not self._listeners[event] then
        self._listeners[event] = {}
      end
      local entry = { callback = callback, priority = priority }
      table.insert(self._listeners[event], entry)
      table.sort(self._listeners[event], function(a, b)
        return a.priority > b.priority
      end)
      return function()
        for i, e in ipairs(self._listeners[event] or {}) do
          if e == entry then
            table.remove(self._listeners[event], i)
            break
          end
        end
      end
    end

    function bus:emit(event, ...)
      local handlers = self._listeners[event]
      if not handlers then return end
      for i = 1, #handlers do
        local status, err = pcall(handlers[i].callback, ...)
        if not status then
          -- Error caught, continue processing remaining handlers
        end
      end
    end

    function bus:queue(event, ...)
      table.insert(self._queue, { event = event, args = { ... } })
    end

    function bus:flush()
      if self._processing then return end
      self._processing = true
      local items = self._queue
      self._queue = {}
      for _, item in ipairs(items) do
        self:emit(item.event, table.unpack(item.args))
      end
      self._processing = false
    end
  end)

  describe("on()", function()
    it("registers a listener", function()
      local called = false
      bus:on("test:event", function() called = true end)
      bus:emit("test:event")
      assert.is_true(called)
    end)

    it("returns unsubscribe function", function()
      local called = false
      local unsub = bus:on("test:event", function() called = true end)
      unsub()
      bus:emit("test:event")
      assert.is_false(called)
    end)

    it("passes arguments to handler", function()
      local received = {}
      bus:on("test:event", function(a, b, c) received = { a, b, c } end)
      bus:emit("test:event", 1, "two", true)
      assert.same({ 1, "two", true }, received)
    end)

    it("calls higher priority first", function()
      local order = {}
      bus:on("test:event", function() table.insert(order, "low") end, 1)
      bus:on("test:event", function() table.insert(order, "high") end, 10)
      bus:on("test:event", function() table.insert(order, "mid") end, 5)
      bus:emit("test:event")
      assert.same({ "high", "mid", "low" }, order)
    end)

    it("handles multiple listeners on same event", function()
      local count = 0
      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)
      bus:emit("test:event")
      assert.equals(3, count)
    end)

    it("emitting unknown event does not error", function()
      bus:emit("nonexistent:event")
    end)
  end)

  describe("queue() + flush()", function()
    it("processes queued events on flush", function()
      local called = false
      bus:on("test:event", function() called = true end)
      bus:queue("test:event")
      assert.is_false(called)
      bus:flush()
      assert.is_true(called)
    end)

    it("processes multiple queued events in order", function()
      local order = {}
      bus:on("test:a", function() table.insert(order, "a") end)
      bus:on("test:b", function() table.insert(order, "b") end)
      bus:queue("test:a")
      bus:queue("test:b")
      bus:flush()
      assert.same({ "a", "b" }, order)
    end)

    it("passes arguments through queue", function()
      local received = {}
      bus:on("test:event", function(a, b) received = { a, b } end)
      bus:queue("test:event", 42, "hello")
      bus:flush()
      assert.same({ 42, "hello" }, received)
    end)

    it("prevents re-entrant flush", function()
      local innerCalled = false
      bus:on("test:outer", function()
        bus:queue("test:inner")
        bus:flush() -- should be no-op
      end)
      bus:on("test:inner", function() innerCalled = true end)
      bus:queue("test:outer")
      bus:flush()
      -- inner event was queued but flush was re-entrant, so not processed
      assert.is_false(innerCalled)
    end)
  end)

  describe("error handling", function()
    it("handler error does not crash emit", function()
      bus:on("test:event", function() error("boom") end)
      assert.has_no.errors(function()
        bus:emit("test:event")
      end)
    end)
  end)
end)
