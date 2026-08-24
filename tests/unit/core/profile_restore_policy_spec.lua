-- tests/unit/core/profile_restore_policy_spec.lua
-- Regression coverage for the boot-time restore bug: profile-selection and
-- enabled/disabled restoration are independent concerns that must both apply
-- whenever they differ from what's already active -- they must never be
-- coupled as if/elseif branches of the same condition (that coupling silently
-- dropped the enabled/disabled restore whenever the profile also changed).

local ProfileRestorePolicy = require("core.profile_restore_policy")

describe("ProfileRestorePolicy.decide", function()
  it("switches profile only when the persisted config differs from the active one", function()
    local decision = ProfileRestorePolicy.decide("Hydra_Medusa_Banuta", "Hydra_Medusa_Banuta", true)
    assert.is_false(decision.switchProfile)
  end)

  it("switches profile when the persisted config differs from the active one", function()
    local decision = ProfileRestorePolicy.decide("OldRoute", "Hydra_Medusa_Banuta", true)
    assert.is_true(decision.switchProfile)
  end)

  it("still applies the persisted enabled state when the profile ALSO needs switching", function()
    -- This is the exact bug: previously this was an `elseif`, so a
    -- simultaneous profile switch + enabled/disabled restore silently
    -- dropped the enabled/disabled half.
    local decision = ProfileRestorePolicy.decide("OldRoute", "Hydra_Medusa_Banuta", false)
    assert.is_true(decision.switchProfile)
    assert.is_true(decision.applyEnabled)
    assert.is_false(decision.enabled)
  end)

  it("applies the persisted enabled state when only enabled/disabled changed", function()
    local decision = ProfileRestorePolicy.decide("Hydra_Medusa_Banuta", "Hydra_Medusa_Banuta", false)
    assert.is_false(decision.switchProfile)
    assert.is_true(decision.applyEnabled)
    assert.is_false(decision.enabled)
  end)

  it("does not request an enabled restore when no enabled value was persisted", function()
    local decision = ProfileRestorePolicy.decide("Hydra_Medusa_Banuta", "Hydra_Medusa_Banuta", nil)
    assert.is_false(decision.applyEnabled)
  end)

  it("does not request a profile switch when nothing was persisted", function()
    local decision = ProfileRestorePolicy.decide("Hydra_Medusa_Banuta", nil, true)
    assert.is_false(decision.switchProfile)
  end)

  it("does not request a profile switch when the persisted value is empty", function()
    local decision = ProfileRestorePolicy.decide("Hydra_Medusa_Banuta", "", true)
    assert.is_false(decision.switchProfile)
  end)
end)
