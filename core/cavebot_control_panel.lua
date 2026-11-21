storage.caveBot = storage.caveBot or {
  forceRefill = false,
  backStop = false,
  backTrainers = false,
  backOffline = false,
}

CaveBot.Control = {}

function CaveBot.Control.request(action)
  if storage.caveBot[action] == nil then return false end
  storage.caveBot[action] = true
  return true
end

function CaveBot.Control.forceRefill() return CaveBot.Control.request("forceRefill") end
function CaveBot.Control.backStop() return CaveBot.Control.request("backStop") end
function CaveBot.Control.backTrainers() return CaveBot.Control.request("backTrainers") end
function CaveBot.Control.backOffline() return CaveBot.Control.request("backOffline") end
