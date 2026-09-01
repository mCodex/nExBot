_G.nExBot = { UI = {} }
local Perf = dofile("ui/core/perf.lua")

describe("Perf (performance tracking)", function()
  before_each(function()
    _G.nExBot.UI.Perf = nil
    Perf = dofile("ui/core/perf.lua")
  end)

  it("records operation timings with ring-buffer bounds", function()
    Perf.begin("render")
    Perf.end_("render")
    assert.is_number(Perf.p95("render"))
    assert.is_number(Perf.p99("render"))
    assert.is_true(Perf.p95("render") >= 0)
  end)

  it("keeps per-op bucket sizes bounded", function()
    for i = 1, 500 do
      Perf.begin("tick")
      Perf.end_("tick")
    end
    local stats = Perf.stats("tick")
    assert.is_true(stats.samples <= Perf.bucketSize)
  end)

  it("unknown op returns nil without error", function()
    assert.is_nil(Perf.p95("never_recorded"))
    assert.is_nil(Perf.stats("never_recorded"))
  end)

  it("begin without end_ does not corrupt stats", function()
    Perf.begin("orphan")
    assert.is_nil(Perf.stats("orphan"))
  end)

  it("unpaired end_ is a no-op", function()
    Perf.end_("phantom")
    assert.is_nil(Perf.stats("phantom"))
  end)
end)
