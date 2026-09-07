-- Run: nvim --headless -u NONE -i NONE -l scripts/benchmark.lua
-- Optional: YANKY_BENCH_RTP=/path/to/baseline YANKY_SQLITE_RTP=/path/to/sqlite.lua
local root = vim.env.YANKY_BENCH_RTP or vim.fn.getcwd()
local database_directory = vim.env.YANKY_BENCH_DIR or (vim.fn.getcwd() .. "/.spec/benchmark")
vim.fn.mkdir(database_directory, "p")
vim.opt.runtimepath:append(root)
if vim.env.YANKY_SQLITE_RTP then
  vim.opt.runtimepath:append(vim.env.YANKY_SQLITE_RTP)
end
local config = require("yanky.config")
local history = require("yanky.history")
local uv = vim.uv or vim.loop
local function measure(label, count, fn)
  local samples = {}
  for run = 1, 5 do
    collectgarbage("collect")
    local start = uv.hrtime()
    for i = 1, count do
      fn(i)
    end
    samples[run] = (uv.hrtime() - start) / 1e6
  end
  table.sort(samples)
  print(
    string.format(
      "%s: median=%.3f ms, min=%.3f ms, max=%.3f ms (%d operations)",
      label,
      samples[3],
      samples[1],
      samples[5],
      count
    )
  )
end
for _, storage in ipairs({ "memory", "shada", "sqlite" }) do
  if storage ~= "sqlite" or pcall(require, "sqlite") then
    for _, size in ipairs({ 1024, 65536 }) do
      local path = database_directory .. "/" .. vim.fn.fnamemodify(vim.fn.tempname(), ":t") .. ".db"
      config.setup({ ring = { storage = storage, storage_path = path, history_length = 100 } })
      history.setup()
      assert(history.storage == require("yanky.storage." .. storage))
      history.clear()
      local payload = string.rep("x", size)
      for i = 1, 100 do
        history.push({ regcontents = payload .. i, regtype = "v", filetype = "text" })
      end
      local count = size == 1024 and 500 or 100
      measure(storage .. " push+sync " .. size .. "B", count, function(i)
        history.push({ regcontents = payload .. i, regtype = "v", filetype = "text" })
      end)
      measure(storage .. " first " .. size .. "B", count, function()
        assert(history.first())
      end)
      measure(storage .. " next " .. size .. "B", count, function(i)
        if i % 100 == 1 then
          history.reset()
        end
        assert(history.next())
      end)
      history.clear()
      vim.fn.delete(path)
    end
  else
    print("sqlite: skipped (set YANKY_SQLITE_RTP to include sqlite.lua)")
  end
end
local yanky = require("yanky")
yanky.setup({ ring = { storage = "memory" }, system_clipboard = { sync_with_ring = false } })
local callbacks = #vim.api.nvim_get_autocmds({ event = "TextYankPost" })
for _ = 1, 20 do
  yanky.setup({ ring = { storage = "memory" }, system_clipboard = { sync_with_ring = false } })
end
print(
  "TextYankPost callbacks after 20 additional setups: "
    .. #vim.api.nvim_get_autocmds({ event = "TextYankPost" })
    .. " (initial "
    .. callbacks
    .. ")"
)
local preserve = require("yanky.preserve_cursor")
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buffer)
local attach = vim.api.nvim_buf_attach
local attachments = 0
vim.api.nvim_buf_attach = function(...)
  attachments = attachments + 1
  return attach(...)
end
for _ = 1, 1000 do
  preserve.yank()
  preserve.on_yank()
end
vim.api.nvim_buf_attach = attach
print("Cursor preservation listeners after 1000 yanks: " .. attachments)
vim.api.nvim_buf_delete(buffer, { force = true })
