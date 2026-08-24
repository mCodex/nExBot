-- Source-scan guard: production UI modules must resolve all colors through the
-- design-system tokens, never hard-code hex colors or unapproved font names.

describe("design-system compliance", function()
  local moduleFiles = {
    "ui/components/components.lua",
    "ui/shell/shell.lua",
    "ui/modules/dashboard.lua",
    "ui/modules/cavebot.lua",
    "ui/modules/targetbot.lua",
    "ui/modules/healing.lua",
    "ui/modules/looting.lua",
    "ui/modules/supplies.lua",
    "ui/modules/scripts.lua",
    "ui/modules/intelligence.lua",
    "ui/modules/profiles.lua",
    "ui/modules/settings.lua",
    "ui/modules/diagnostics.lua",
    "ui/modules/page.lua",
  }

  it("no production module hard-codes hex colors", function()
    for _, path in ipairs(moduleFiles) do
      local f = assert(io.open(path, "r"))
      local source = f:read("*a")
      f:close()
      assert.is_nil(source:find("#%x%x%x%x%x%x", 1), "hex color in " .. path)
      assert.is_nil(source:find("#%x%x%x%x", 1), "hex color in " .. path)
    end
  end)

  it("no production module hard-codes unapproved font names", function()
    for _, path in ipairs(moduleFiles) do
      local f = assert(io.open(path, "r"))
      local source = f:read("*a")
      f:close()
      for font in source:gmatch('setFont%("([^"]+)"') do
        assert.is_truthy(
          font == "verdana-11px-rounded" or font == "verdana-11px-monochrome" or font == "terminus-10px" or font == "cipsoftFont",
          "unapproved font " .. font .. " in " .. path
        )
      end
    end
  end)
end)
