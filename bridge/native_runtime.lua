local dispatch = nexbotDecide
if not dispatch or not json or not json.encode or not json.decode then return end

nExBotRuntime = {}

function nExBotRuntime.decide(operation, observation)
  local encoded, input = pcall(json.encode, observation)
  if not encoded then return end
  local answer = dispatch(operation, input)
  if type(answer) ~= "string" or answer == "" then return end

  local decoded, decision = pcall(json.decode, answer)
  if decoded then return decision end
end
