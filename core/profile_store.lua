local ProfileStore = {}

local function safeName(name)
  return type(name) == "string" and name ~= "" and not name:find("[/\\]") and name ~= "." and name ~= ".."
end

local function decodeCfg(content)
  local rows = {}
  for line in tostring(content or ""):gmatch("[^\r\n]+") do
    local action, value = line:match("^([^:]+):(.*)$")
    if action then rows[#rows + 1] = { action, value } end
  end
  return rows
end

local function encodeCfg(rows)
  local lines = {}
  for index, row in ipairs(rows or {}) do
    lines[index] = tostring(row[1]) .. ":" .. tostring(row[2] or "")
  end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

function ProfileStore.open(options)
  local key = assert(options.key, "profile key is required")
  local extension = assert(options.extension, "profile extension is required")
  local directory = "/bot/" .. nExBot.paths.config .. "/" .. key .. "/"
  local suffix = "." .. extension
  storage._configs = storage._configs or {}
  local state = storage._configs[key] or {}
  storage._configs[key] = state
  if type(state.selected) == "string" and state.selected:sub(-#suffix) == suffix then
    state.selected = state.selected:sub(1, -#suffix - 1)
  end

  local function path(name) return directory .. name .. "." .. extension end
  local function decode(content)
    if extension == "cfg" then return decodeCfg(content) end
    return json.decode(content)
  end
  local function encode(data)
    if extension == "cfg" then return encodeCfg(data) end
    return json.encode(data, 2)
  end
  local function load(name)
    if not safeName(name) then return nil, "Invalid profile name" end
    local ok, content = pcall(g_resources.readFileContents, path(name))
    if not ok or content == nil then return nil, "Profile not found" end
    local decoded, data = pcall(decode, content)
    if not decoded then return nil, tostring(data) end
    return data
  end

  local store = {}
  function store.list()
    local ok, files = pcall(g_resources.listDirectoryFiles, directory, false, false)
    if not ok or type(files) ~= "table" then return {} end
    local profiles = {}
    for _, file in ipairs(files) do
      local name = tostring(file):match("([^/\\]+)$") or tostring(file)
      if name:sub(-#suffix) == suffix then profiles[#profiles + 1] = name:sub(1, -#suffix - 1) end
    end
    table.sort(profiles)
    return profiles
  end
  function store.isOn() return state.enabled == true end
  function store.current() return state.selected end
  function store.load(name) return load(name or state.selected) end
  function store.select(name)
    local data, reason = load(name)
    if not data then return false, reason end
    state.selected = name
    options.onChange(name, store.isOn(), data)
    return true
  end
  function store.save(data)
    if not safeName(state.selected) then return false, "No profile selected" end
    local ok, reason = pcall(g_resources.writeFileContents, path(state.selected), encode(data))
    return ok, ok and nil or tostring(reason)
  end
  function store.create(name, data)
    if not safeName(name) then return false, "Invalid profile name" end
    if g_resources.fileExists and g_resources.fileExists(path(name)) then return false, "Profile already exists" end
    state.selected = name
    local ok, reason = store.save(data or (extension == "cfg" and {} or { targeting = {}, looting = {} }))
    if ok then options.onChange(name, store.isOn(), data or store.load(name)) end
    return ok, reason
  end
  function store.remove(name)
    if not safeName(name) then return false, "Invalid profile name" end
    local ok, reason = pcall(g_resources.deleteFile, path(name))
    if not ok then return false, tostring(reason) end
    if state.selected == name then state.selected = store.list()[1] end
    store.reload()
    return true
  end
  function store.rename(oldName, newName)
    if not safeName(oldName) or not safeName(newName) then return false, "Invalid profile name" end
    if g_resources.fileExists and g_resources.fileExists(path(newName)) then return false, "Profile already exists" end
    local data, reason = load(oldName)
    if not data then return false, reason end
    local ok, writeReason = pcall(g_resources.writeFileContents, path(newName), encode(data))
    if not ok then return false, tostring(writeReason) end
    local removed, removeReason = pcall(g_resources.deleteFile, path(oldName))
    if not removed then
      pcall(g_resources.deleteFile, path(newName))
      return false, tostring(removeReason)
    end
    if state.selected == oldName then state.selected = newName end
    store.reload()
    return true
  end
  function store.setOn()
    state.enabled = true
    options.onChange(state.selected, true, store.load())
  end
  function store.setOff()
    state.enabled = false
    options.onChange(state.selected, false, store.load())
  end
  function store.reload()
    options.onChange(state.selected, store.isOn(), store.load())
  end

  return store
end

nExBot.ProfileStore = ProfileStore
return ProfileStore
