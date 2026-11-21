IntelligenceCalibration = {}
local Calibration = IntelligenceCalibration
Calibration.__index = Calibration

function Calibration.new(bucketCount)
  bucketCount = bucketCount or 10
  assert(bucketCount >= 1 and bucketCount % 1 == 0, "bucket count must be a positive integer")
  local buckets = {}
  for index = 1, bucketCount do buckets[index] = { count = 0, predicted = 0, actual = 0 } end
  return setmetatable({ bucketCount = bucketCount, buckets = buckets }, Calibration)
end

function Calibration:observe(confidence, success)
  assert(type(confidence) == "number" and confidence >= 0 and confidence <= 1, "confidence must be in [0, 1]")
  local bucket = self.buckets[math.min(self.bucketCount, math.floor(confidence * self.bucketCount) + 1)]
  bucket.count = bucket.count + 1
  bucket.predicted = bucket.predicted + confidence
  bucket.actual = bucket.actual + (success and 1 or 0)
end

function Calibration:report()
  local report = {}
  for index, bucket in ipairs(self.buckets) do
    local count = bucket.count
    local predicted, actual = count == 0 and 0 or bucket.predicted / count, count == 0 and 0 or bucket.actual / count
    report[index] = { count = count, predicted = predicted, actual = actual, error = math.abs(actual - predicted) }
  end
  return report
end

return Calibration
