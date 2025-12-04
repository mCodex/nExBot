--[[
  nExBot Test Framework
  Unit testing infrastructure for the bot
  
  Author: nExBot Team
  Version: 1.0.0
]]

local TestFramework = {
  suites = {},
  currentSuite = nil
}

-- Create a new test suite
function TestFramework:new(name)
  local suite = {
    name = name,
    tests = {},
    passed = 0,
    failed = 0,
    skipped = 0,
    errors = {},
    beforeAll = nil,
    afterAll = nil,
    beforeEach = nil,
    afterEach = nil,
    startTime = 0,
    endTime = 0
  }
  
  setmetatable(suite, { __index = self })
  return suite
end

-- Add a test to the suite
function TestFramework:test(testName, testFunc)
  table.insert(self.tests, {
    name = testName,
    func = testFunc,
    skip = false
  })
  return self
end

-- Add a skipped test
function TestFramework:skip(testName, testFunc)
  table.insert(self.tests, {
    name = testName,
    func = testFunc,
    skip = true
  })
  return self
end

-- Set before all hook
function TestFramework:setBeforeAll(func)
  self.beforeAll = func
  return self
end

-- Set after all hook
function TestFramework:setAfterAll(func)
  self.afterAll = func
  return self
end

-- Set before each hook
function TestFramework:setBeforeEach(func)
  self.beforeEach = func
  return self
end

-- Set after each hook
function TestFramework:setAfterEach(func)
  self.afterEach = func
  return self
end

-- Assertion: equals
function TestFramework:assertEquals(actual, expected, message)
  if actual ~= expected then
    error(string.format("Assertion failed: %s\nExpected: %s\nActual: %s",
      message or "Values not equal",
      tostring(expected),
      tostring(actual)))
  end
end

-- Assertion: not equals
function TestFramework:assertNotEquals(actual, expected, message)
  if actual == expected then
    error(string.format("Assertion failed: %s\nExpected NOT: %s\nActual: %s",
      message or "Values are equal",
      tostring(expected),
      tostring(actual)))
  end
end

-- Assertion: true
function TestFramework:assertTrue(condition, message)
  if not condition then
    error(string.format("Assertion failed: %s", message or "Expected true, got false"))
  end
end

-- Assertion: false
function TestFramework:assertFalse(condition, message)
  if condition then
    error(string.format("Assertion failed: %s", message or "Expected false, got true"))
  end
end

-- Assertion: nil
function TestFramework:assertNil(value, message)
  if value ~= nil then
    error(string.format("Assertion failed: %s\nExpected nil, got: %s",
      message or "Value is not nil",
      tostring(value)))
  end
end

-- Assertion: not nil
function TestFramework:assertNotNil(value, message)
  if value == nil then
    error(string.format("Assertion failed: %s", message or "Value is nil"))
  end
end

-- Assertion: type check
function TestFramework:assertType(value, expectedType, message)
  local actualType = type(value)
  if actualType ~= expectedType then
    error(string.format("Assertion failed: %s\nExpected type: %s\nActual type: %s",
      message or "Type mismatch",
      expectedType,
      actualType))
  end
end

-- Assertion: table contains
function TestFramework:assertContains(table, value, message)
  for _, v in pairs(table) do
    if v == value then
      return
    end
  end
  error(string.format("Assertion failed: %s\nValue not found in table: %s",
    message or "Table does not contain value",
    tostring(value)))
end

-- Assertion: table length
function TestFramework:assertLength(table, expectedLength, message)
  local actualLength = #table
  if actualLength ~= expectedLength then
    error(string.format("Assertion failed: %s\nExpected length: %d\nActual length: %d",
      message or "Table length mismatch",
      expectedLength,
      actualLength))
  end
end

-- Assertion: throws error
function TestFramework:assertThrows(func, message)
  local success, _ = pcall(func)
  if success then
    error(string.format("Assertion failed: %s", message or "Expected function to throw"))
  end
end

-- Assertion: greater than
function TestFramework:assertGreaterThan(actual, expected, message)
  if not (actual > expected) then
    error(string.format("Assertion failed: %s\nExpected > %s, got %s",
      message or "Value not greater",
      tostring(expected),
      tostring(actual)))
  end
end

-- Assertion: less than
function TestFramework:assertLessThan(actual, expected, message)
  if not (actual < expected) then
    error(string.format("Assertion failed: %s\nExpected < %s, got %s",
      message or "Value not less",
      tostring(expected),
      tostring(actual)))
  end
end

-- Run all tests in the suite
function TestFramework:run(verbose)
  verbose = verbose ~= false
  
  self.passed = 0
  self.failed = 0
  self.skipped = 0
  self.errors = {}
  self.startTime = os.time()
  
  if verbose then
    print(string.format("\n========== Running Test Suite: %s ==========\n", self.name))
  end
  
  -- Run beforeAll hook
  if self.beforeAll then
    local success, err = pcall(self.beforeAll)
    if not success then
      print(string.format("✗ beforeAll hook failed: %s", err))
      return self
    end
  end
  
  -- Run each test
  for _, test in ipairs(self.tests) do
    if test.skip then
      self.skipped = self.skipped + 1
      if verbose then
        print(string.format("⊘ %s (skipped)", test.name))
      end
    else
      -- Run beforeEach hook
      if self.beforeEach then
        local success, err = pcall(self.beforeEach)
        if not success then
          self.failed = self.failed + 1
          table.insert(self.errors, {
            test = test.name,
            error = "beforeEach hook failed: " .. tostring(err)
          })
          if verbose then
            print(string.format("✗ %s: beforeEach failed - %s", test.name, err))
          end
          goto continue
        end
      end
      
      -- Run the test
      local success, err = pcall(function()
        test.func(self)
      end)
      
      if success then
        self.passed = self.passed + 1
        if verbose then
          print(string.format("✓ %s", test.name))
        end
      else
        self.failed = self.failed + 1
        table.insert(self.errors, {
          test = test.name,
          error = tostring(err)
        })
        if verbose then
          print(string.format("✗ %s: %s", test.name, err))
        end
      end
      
      -- Run afterEach hook
      if self.afterEach then
        pcall(self.afterEach)
      end
      
      ::continue::
    end
  end
  
  -- Run afterAll hook
  if self.afterAll then
    pcall(self.afterAll)
  end
  
  self.endTime = os.time()
  
  -- Print summary
  if verbose then
    print(string.format("\n========== Results =========="))
    print(string.format("Passed:  %d", self.passed))
    print(string.format("Failed:  %d", self.failed))
    print(string.format("Skipped: %d", self.skipped))
    print(string.format("Total:   %d", self.passed + self.failed + self.skipped))
    print(string.format("Time:    %ds", self.endTime - self.startTime))
    
    if #self.errors > 0 then
      print(string.format("\n========== Errors =========="))
      for _, err in ipairs(self.errors) do
        print(string.format("\n[%s]", err.test))
        print(err.error)
      end
    end
  end
  
  return self
end

-- Get test results
function TestFramework:getResults()
  return {
    name = self.name,
    passed = self.passed,
    failed = self.failed,
    skipped = self.skipped,
    errors = self.errors,
    duration = self.endTime - self.startTime,
    success = self.failed == 0
  }
end

-- Create mock object
function TestFramework:createMock(template)
  local mock = {
    _calls = {},
    _returns = {}
  }
  
  -- Create mock functions from template
  if template then
    for key, value in pairs(template) do
      if type(value) == "function" then
        mock[key] = function(...)
          table.insert(mock._calls, {
            method = key,
            args = {...}
          })
          
          local returnValue = mock._returns[key]
          if type(returnValue) == "function" then
            return returnValue(...)
          end
          return returnValue
        end
      else
        mock[key] = value
      end
    end
  end
  
  -- Set return value for mock function
  mock._setReturn = function(method, value)
    mock._returns[method] = value
  end
  
  -- Get call count for method
  mock._getCallCount = function(method)
    local count = 0
    for _, call in ipairs(mock._calls) do
      if call.method == method then
        count = count + 1
      end
    end
    return count
  end
  
  -- Get all calls to method
  mock._getCalls = function(method)
    local calls = {}
    for _, call in ipairs(mock._calls) do
      if call.method == method then
        table.insert(calls, call.args)
      end
    end
    return calls
  end
  
  -- Reset mock
  mock._reset = function()
    mock._calls = {}
  end
  
  return mock
end

return TestFramework
