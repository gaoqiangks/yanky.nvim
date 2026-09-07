local stub = require("luassert.stub")
local config = require("yanky.config")
local history = require("yanky.history")

for _, backend in ipairs({ "memory", "shada", "sqlite" }) do
  describe(backend .. " storage", function()
    local path, saved_history
    before_each(function()
      saved_history = vim.g.YANKY_HISTORY
      path = vim.fn.tempname() .. ".db"
      config.setup({ ring = { storage = backend, storage_path = path, history_length = 3 } })
      history.setup()
      assert.are.equal(require("yanky.storage." .. backend), history.storage)
      history.clear()
    end)

    after_each(function()
      history.clear()
      vim.fn.delete(path)
      vim.g.YANKY_HISTORY = saved_history
      require("yanky").setup({ ring = { storage = "memory" } })
    end)

    it("deduplicates content and type while retaining different register types", function()
      history.push({ regcontents = "one", regtype = "v" })
      history.push({ regcontents = "one", regtype = "v", filetype = "lua" })
      assert.are.equal(1, #history.all())
      history.push({ regcontents = "one", regtype = "V" })
      assert.are.equal(2, #history.all())
    end)

    it("caps history, cycles in order, and handles both boundaries", function()
      for i = 1, 5 do
        history.push({ regcontents = tostring(i), regtype = "v" })
      end
      assert.are.equal(3, #history.all())
      history.reset()
      for i = 5, 3, -1 do
        assert.are.equal(tostring(i), history.next().regcontents)
      end
      assert.is_nil(history.next())
      assert.are.equal("4", history.previous().regcontents)
      assert.are.equal("5", history.previous().regcontents)
      assert.is_nil(history.previous())
    end)

    it("deletes entries and supports empty history", function()
      assert.is_nil(history.first())
      history.push({ regcontents = "older", regtype = "v" })
      history.push({ regcontents = "newer", regtype = "v" })
      history.delete(1)
      assert.are.equal("older", history.first().regcontents)
      history.clear()
      assert.is_nil(history.first())
      assert.is_nil(history.next())
    end)

    if backend == "sqlite" then
      it("reopens persisted entries and respects bounded reads", function()
        for i = 1, 3 do
          history.push({ regcontents = tostring(i), regtype = "v" })
        end
        history.setup()
        assert.are.equal("3", history.first().regcontents)
        assert.are.equal(2, #history.storage.all(2))
        assert.are.equal(3, #history.storage.all())
      end)

      it("rolls back an insert if trimming fails", function()
        history.push({ regcontents = "original", regtype = "v" })
        local db = history.storage.db
        db:with_open(function()
          db:eval("CREATE TRIGGER fail_trim BEFORE DELETE ON history BEGIN SELECT RAISE(ABORT, 'trim failed'); END")
        end)
        history.config.history_length = 1
        assert.has_error(function()
          history.push({ regcontents = "new", regtype = "v" })
        end)
        assert.are.equal(1, #history.all())
        assert.are.equal("original", history.first().regcontents)
        db:with_open(function()
          db:eval("DROP TRIGGER fail_trim")
        end)
        history.push({ regcontents = "recovered", regtype = "v" })
        assert.are.equal("recovered", history.first().regcontents)
      end)
    end
  end)
end

describe("SQLite fallback", function()
  it("initializes memory storage when opening the database fails", function()
    local sqlite = package.loaded.sqlite
    local notify = stub(vim, "notify")
    package.loaded.sqlite = {
      open = function()
        return nil
      end,
    }
    config.setup({ ring = { storage = "sqlite", storage_path = "test.db", history_length = 2 } })
    local ok, err = pcall(history.setup)
    package.loaded.sqlite = sqlite
    notify:revert()
    assert.is_true(ok, tostring(err))
    assert.are.equal(require("yanky.storage.memory"), history.storage)
    history.clear()
    for i = 1, 3 do
      history.push({ regcontents = tostring(i), regtype = "v" })
    end
    assert.are.equal(2, #history.all())
    history.clear()
  end)
end)
