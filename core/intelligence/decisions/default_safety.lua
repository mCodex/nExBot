if not IntelligenceSafetyEnvelope then dofile("core/intelligence/decisions/safety_envelope.lua") end

IntelligenceDefaultSafety = {}

function IntelligenceDefaultSafety.new()
  return IntelligenceSafetyEnvelope.new({ validators = {
    { name = "health", check = function(proposal, context)
      if proposal.minHealthRatio and context.healthRatio and context.healthRatio < proposal.minHealthRatio then
        return false, "health_below_hard_limit"
      end
      return true
    end },
    { name = "confidence", check = function(proposal)
      if proposal.minConfidence and (proposal.confidence or 0) < proposal.minConfidence then
        return false, "confidence_below_threshold"
      end
      return true
    end },
    { name = "target", check = function(proposal, context)
      if proposal.action == "attack" and context.targetValid == false then return false, "invalid_target" end
      return true
    end },
    { name = "floor", check = function(proposal, context)
      if proposal.action == "move" and proposal.position and context.playerPosition
        and proposal.position.z ~= context.playerPosition.z then return false, "invalid_movement_floor" end
      return true
    end },
  } })
end

return IntelligenceDefaultSafety
