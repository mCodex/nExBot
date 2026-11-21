describe("CombatFrameRecorder", function()
  local CFR

  before_each(function()
    _G.CombatFrameRecorder = nil
    CFR = dofile("targetbot/application/combat_frame.lua")
    CFR.new()
  end)

  it("creates a frame with tickId and timestamp on begin", function()
    local frame = CFR:begin({ timestamp = 1000, playerState = { hp = 500 } })
    assert.equals(1, frame.tickId)
    assert.equals(1000, frame.timestamp)
    assert.same({ hp = 500 }, frame.playerState)
  end)

  it("increments tickId on each begin", function()
    CFR:begin({ timestamp = 100 })
    CFR:finish()
    local frame2 = CFR:begin({ timestamp = 200 })
    assert.equals(2, frame2.tickId)
  end)

  it("records candidate targets", function()
    CFR:begin({})
    CFR:record("candidate", { id = 1, score = 100 })
    CFR:record("candidate", { id = 2, score = 200 })
    local frame = CFR:finish()
    assert.equals(2, #frame.candidateTargets)
    assert.equals(1, frame.candidateTargets[1].id)
    assert.equals(2, frame.candidateTargets[2].id)
  end)

  it("records reachability results", function()
    CFR:begin({})
    CFR:record("reachability", { id = 1, state = "ATTACKABLE_NOW" })
    local frame = CFR:finish()
    assert.equals(1, #frame.reachabilityResults)
  end)

  it("records movement intents and rejections", function()
    CFR:begin({})
    CFR:record("movementIntent", { source = "chase", type = 7 })
    CFR:record("rejectedIntent", { source = "lure", reason = "commitment" })
    local frame = CFR:finish()
    assert.equals(1, #frame.movementIntents)
    assert.equals(1, #frame.rejectedIntents)
    assert.equals("commitment", frame.rejectedIntents[1].reason)
  end)

  it("records reason codes", function()
    CFR:begin({})
    CFR:record("reasonCode", "TARGET_RETAINED_FINISH_COMMITMENT")
    CFR:record("reasonCode", "REPLACEMENT_REJECTED_UNREACHABLE")
    local frame = CFR:finish()
    assert.equals(2, #frame.reasonCodes)
  end)

  it("sets selected target and movement on finish", function()
    CFR:begin({})
    local frame = CFR:finish({
      selectedTarget = { id = 5, reason = "best_score" },
      selectedMovementIntent = { type = "chase", source = "event" },
      attackStateAfter = "LOCKED",
      durationMs = 1.5,
    })
    assert.equals(5, frame.selectedTarget.id)
    assert.equals("chase", frame.selectedMovementIntent.type)
    assert.equals("LOCKED", frame.attackStateAfter)
    assert.equals(1.5, frame.durationMs)
  end)

  it("stores frames in bounded ring buffer (256 max)", function()
    for i = 1, 300 do
      CFR:begin({ timestamp = i })
      CFR:finish()
    end
    assert.equals(256, CFR:getCount())
  end)

  it("getRecent returns most recent frames in reverse order", function()
    for i = 1, 5 do
      CFR:begin({ timestamp = i * 100 })
      CFR:finish()
    end
    local recent = CFR:getRecent(3)
    assert.equals(3, #recent)
    assert.equals(500, recent[1].timestamp)
    assert.equals(400, recent[2].timestamp)
    assert.equals(300, recent[3].timestamp)
  end)

  it("reset clears all state", function()
    CFR:begin({})
    CFR:finish()
    CFR:reset()
    assert.equals(0, CFR:getCount())
    local recent = CFR:getRecent(10)
    assert.equals(0, #recent)
  end)
end)
