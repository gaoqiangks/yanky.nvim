local yanky = require("yanky")
local utils = require("yanky.utils")

describe("Clipboard reads", function()
  local reads
  local clipboard
  local saved_clipboard

  before_each(function()
    saved_clipboard = vim.g.clipboard
    reads = 0
    clipboard = { { "clipboard text" }, "v" }
    local function paste()
      reads = reads + 1
      return clipboard
    end
    local function copy(lines, regtype)
      clipboard = { lines, regtype }
    end
    vim.g.clipboard = {
      name = "yanky-test",
      copy = { ["+"] = copy, ["*"] = copy },
      paste = { ["+"] = paste, ["*"] = paste },
      cache_enabled = 0,
    }
    vim.fn["provider#clipboard#Executable"]()
    yanky.setup({ ring = { storage = "memory" }, system_clipboard = { sync_with_ring = false } })
    yanky.history.clear()
    reads = 0
  end)

  after_each(function()
    vim.g.clipboard = saved_clipboard
    vim.fn["provider#clipboard#Executable"]()
  end)

  it("can still read external clipboard contents", function()
    assert.are.same({ regcontents = "clipboard text", regtype = "v" }, utils.get_register_info("+"))
  end)

  it("records a clipboard yank without reading the provider", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second" })
    utils.normal('gg"+2yy')
    assert.are.equal(0, reads)
    assert.are.equal("first\nsecond\n", yanky.history.first().regcontents)
    assert.are.equal("V", yanky.history.first().regtype)
  end)
end)

describe("Register conversion", function()
  for _, regtype in ipairs({ "v", "V", "\0223" }) do
    it("preserves contents for register type " .. regtype, function()
      vim.fn.setreg("a", { "first", "", "last", "" }, regtype)
      assert.are.same({
        regcontents = vim.fn.getreg("a"),
        regtype = vim.fn.getregtype("a"),
      }, utils.register_info_from_lines(vim.fn.getreg("a", 1, true), vim.fn.getregtype("a")))
    end)
  end

  it("evaluates the expression register", function()
    vim.fn.setreg("=", '"result"')
    assert.are.equal("result", utils.get_register_info("=").regcontents)
  end)

  it("retains accumulated text when appending to a register", function()
    yanky.history.clear()
    vim.fn.setreg("a", "old", "v")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "new" })
    utils.normal('gg"Ay$')
    assert.are.equal("oldnew", yanky.history.first().regcontents)
  end)
end)

describe("ShaDa history", function()
  local saved_history
  before_each(function()
    saved_history = vim.g.YANKY_HISTORY
    yanky.setup({ ring = { storage = "shada", history_length = 10 } })
    yanky.history.clear()
  end)

  after_each(function()
    vim.g.YANKY_HISTORY = saved_history
    yanky.setup({ ring = { storage = "memory" } })
  end)

  it("limits history and keeps numbered registers in newest-first order", function()
    for i = 1, 12 do
      yanky.history.push({ regcontents = tostring(i), regtype = "v" })
    end
    assert.are.equal(10, #yanky.history.all())
    for i = 1, 9 do
      assert.are.equal(tostring(13 - i), vim.fn.getreg(tostring(i)))
    end
    yanky.history.delete(2)
    assert.are.equal("10", yanky.history.all()[2].regcontents)
    local copy = yanky.history.all()
    copy[1].regcontents = "changed"
    assert.are.equal("12", yanky.history.first().regcontents)
  end)

  it("can push before the ShaDa global has been initialized", function()
    vim.g.YANKY_HISTORY = nil
    yanky.history.push({ regcontents = "first", regtype = "v" })
    assert.are.equal("first", yanky.history.first().regcontents)
  end)
end)
