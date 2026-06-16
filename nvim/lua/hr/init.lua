-- ============================================================
--                         hr
-- ============================================================
-- A reading-list sidebar backed by the `hr` CLI.
-- Public API:
--   require("hr").setup({ binary = "...", vault = "...", side = "left",
--                          width = 60, show_read = true })
--   require("hr").open() / close() / toggle() / refresh() / start()
-- `start()` opens the panel AND the top article in the main window
-- (entry point from the `hr` CLI; avoids the empty [No Name] buffer).
-- Buffer-local keys (active only in the sidebar):
--   <CR>/o open   r read   u unread   f fav   a alias
--   R refresh   s sync   q close   ? help

local M = {}

local state = {
   bufnr      = nil,
   winid      = nil,
   prev_winid = nil,
   items      = {},
}

local config = {
   binary    = "hr",
   vault     = nil,
   side      = "left",
   width     = 60,
   show_read = true,
}

local function is_open()
   return state.winid ~= nil
      and vim.api.nvim_win_is_valid(state.winid)
end

local function read_vault_from_rc()
   local f = io.open(vim.fn.expand("~/.hrrc"), "r")
   if not f then return nil end
   local content = f:read("*a")
   f:close()
   return content:match('vault%s*=%s*"([^"]+)"')
end

local function resolve_vault()
   if config.vault and config.vault ~= "" then
      return config.vault
   end
   return read_vault_from_rc()
end

local function base_cmd()
   local cmd = { config.binary }
   if config.vault then
      table.insert(cmd, "-C")
      table.insert(cmd, config.vault)
   end
   return cmd
end

local function run(args)
   local cmd = base_cmd()
   for _, a in ipairs(args) do table.insert(cmd, a) end
   local out = vim.fn.system(cmd)
   if vim.v.shell_error ~= 0 then
      vim.notify("hr: " .. (out or ""), vim.log.levels.ERROR)
      return nil
   end
   return out
end

local function fetch_items()
   local args = { "list", "--json" }
   if not config.show_read then
      table.insert(args, "--unread")
   end
   local out = run(args)
   if not out or out == "" then return {} end
   local ok, decoded = pcall(vim.json.decode, out)
   if not ok or type(decoded) ~= "table" then return {} end
   return decoded
end

local function render(items)
   local lines = {}
   local feed_w = 4
   for _, it in ipairs(items) do
      local f = it.feed or ""
      if #f > feed_w then feed_w = #f end
   end
   if feed_w > 20 then feed_w = 20 end
   for _, it in ipairs(items) do
      local r   = it.read and "R" or " "
      local fav = it.favorite and "F" or " "
      local date = (it.published or ""):sub(1, 10)
      local feed = (it.feed or ""):sub(1, feed_w)
      local label = (it.alias ~= nil and it.alias ~= "")
         and it.alias or (it.title or "")
      local line = string.format(
         "[%s%s] %s  %-" .. feed_w .. "s  %s",
         r, fav, date, feed, label)
      table.insert(lines, line)
   end
   return lines
end

local function redraw()
   if not is_open() then return end
   state.items = fetch_items()
   local lines = render(state.items)
   if #lines == 0 then lines = { "(no articles)" } end
   vim.bo[state.bufnr].modifiable = true
   vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
   vim.bo[state.bufnr].modifiable = false
end

local function current_item()
   if not is_open() then return nil end
   local row = vim.api.nvim_win_get_cursor(state.winid)[1]
   return state.items[row]
end

local function open_current()
   local it = current_item()
   if not it then return end
   local target = state.prev_winid
   if not (target
      and vim.api.nvim_win_is_valid(target)
      and target ~= state.winid) then
      target = nil
   end
   if target then
      vim.api.nvim_set_current_win(target)
   else
      vim.cmd("wincmd l")
      if vim.api.nvim_get_current_win() == state.winid then
         vim.cmd("rightbelow vsplit")
      end
   end
   vim.cmd("edit " .. vim.fn.fnameescape(it.path))
   state.prev_winid = vim.api.nvim_get_current_win()
end

local function act(cmd)
   local it = current_item()
   if not it then return end
   run({ cmd, it.path })
   redraw()
end

local function rename_current()
   local it = current_item()
   if not it then return end
   local default = (it.alias ~= nil and it.alias ~= "")
      and it.alias or (it.title or "")
   vim.ui.input(
      { prompt = "Alias (empty to clear): ", default = default },
      function(new)
         if new == nil then return end
         run({ "alias", it.path, new })
         redraw()
      end)
end

local function sync_then_redraw()
   run({ "sync" })
   redraw()
end

local function show_help()
   vim.notify(
      "hr keys:\n" ..
      "  <CR>/o  open article\n" ..
      "  r       mark read\n" ..
      "  u       mark unread\n" ..
      "  f       toggle favorite\n" ..
      "  a       set alias (rename label)\n" ..
      "  R       refresh\n" ..
      "  s       sync + refresh\n" ..
      "  q       close panel\n" ..
      "  ?       this help",
      vim.log.levels.INFO)
end

local function setup_keymaps(bufnr)
   local opts = { buffer = bufnr, nowait = true, silent = true }
   local map = vim.keymap.set
   map("n", "<CR>", open_current,                    opts)
   map("n", "o",    open_current,                    opts)
   map("n", "r",    function() act("read")   end,    opts)
   map("n", "u",    function() act("unread") end,    opts)
   map("n", "f",    function() act("fav")    end,    opts)
   map("n", "a",    rename_current,                  opts)
   map("n", "R",    redraw,                          opts)
   map("n", "s",    sync_then_redraw,                opts)
   map("n", "q",    M.close,                         opts)
   map("n", "?",    show_help,                       opts)
end

function M.open()
   if is_open() then
      vim.api.nvim_set_current_win(state.winid)
      return
   end
   local vault = resolve_vault()
   if vault then
      vim.cmd("silent! cd " .. vim.fn.fnameescape(vault))
   end
   state.prev_winid = vim.api.nvim_get_current_win()

   local bufnr = vim.api.nvim_create_buf(false, true)
   vim.bo[bufnr].buftype   = "nofile"
   vim.bo[bufnr].bufhidden = "wipe"
   vim.bo[bufnr].swapfile  = false
   vim.bo[bufnr].filetype  = "hr"
   vim.api.nvim_buf_set_name(bufnr, "hr://reading-list")
   state.bufnr = bufnr

   local prefix = config.side == "left" and "topleft" or "botright"
   vim.cmd(prefix .. " " .. config.width .. "vnew")
   state.winid = vim.api.nvim_get_current_win()
   vim.api.nvim_win_set_buf(state.winid, bufnr)

   vim.wo[state.winid].number         = true
   vim.wo[state.winid].relativenumber = false
   vim.wo[state.winid].wrap           = false
   vim.wo[state.winid].signcolumn     = "no"
   vim.wo[state.winid].cursorline     = true
   vim.wo[state.winid].winfixwidth    = true

   setup_keymaps(bufnr)
   redraw()

   vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(state.winid),
      once    = true,
      callback = function()
         state.winid = nil
         state.bufnr = nil
         state.items = {}
      end,
   })
end

function M.close()
   if is_open() then
      vim.api.nvim_win_close(state.winid, true)
   end
end

function M.toggle()
   if is_open() then M.close() else M.open() end
end

function M.refresh() redraw() end

-- start opens the panel and closes the initial empty [No Name] window
-- if there is one. Entry point from the `hr` CLI: panel only, no
-- placeholder buffer, no article auto-opened.
function M.start()
   M.open()
   local prev = state.prev_winid
   if not (prev and prev ~= state.winid
      and vim.api.nvim_win_is_valid(prev)) then
      return
   end
   local buf = vim.api.nvim_win_get_buf(prev)
   if vim.api.nvim_buf_get_name(buf) == ""
      and not vim.bo[buf].modified
      and vim.api.nvim_buf_line_count(buf) <= 1 then
      pcall(vim.api.nvim_win_close, prev, false)
   end
end

function M.setup(opts)
   if opts then
      for k, v in pairs(opts) do config[k] = v end
   end
end

return M
