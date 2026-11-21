-- core/profile_restore_policy.lua
-- Pure decision logic for boot-time restoration from UnifiedStorage.
--
-- Profile selection ("which .cfg/.json is active") and enabled/disabled state
-- are independent concerns: whichever ones differ from what's already active
-- must be restored, regardless of whether the other one also changed. This
-- module exists because that independence was previously encoded as an
-- if/elseif in core/configs.lua, which silently skipped the enabled/disabled
-- restore whenever the profile also needed switching.

-- OTClient's sandbox has no `package`/`_G`, and `dofile` discards return
-- values -- the codebase communicates via plain (non-local) globals, same
-- convention as core/safe_call.lua.
ProfileRestorePolicy = ProfileRestorePolicy or {}

function ProfileRestorePolicy.decide(currentSelected, persistedConfig, persistedEnabled)
  local hasPersistedConfig = type(persistedConfig) == "string" and persistedConfig ~= ""
  return {
    switchProfile = hasPersistedConfig and persistedConfig ~= currentSelected,
    applyEnabled = persistedEnabled ~= nil,
    enabled = persistedEnabled,
  }
end

return ProfileRestorePolicy
