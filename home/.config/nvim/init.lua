-- ~/.config/nvim/init.lua - Neovim configuration

-- Basic settings
vim.opt.number = true              -- Show line numbers
vim.opt.relativenumber = true      -- Show relative line numbers
vim.opt.mouse = 'a'                -- Enable mouse support
vim.opt.clipboard = 'unnamedplus'  -- Use system clipboard
vim.opt.wrap = false               -- Don't wrap lines
vim.opt.breakindent = true         -- Enable break indent
vim.opt.undofile = true            -- Save undo history
vim.opt.ignorecase = true          -- Case insensitive searching
vim.opt.smartcase = true           -- Case sensitive if uppercase present
vim.opt.signcolumn = 'yes'         -- Keep signcolumn on by default
vim.opt.updatetime = 250           -- Decrease update time
vim.opt.timeoutlen = 300           -- Decrease mapped sequence wait time
vim.opt.completeopt = 'menuone,noselect'  -- Better completion experience
vim.opt.termguicolors = true       -- Enable 24-bit RGB colors

-- Indentation
vim.opt.tabstop = 4                -- Number of spaces tabs count for
vim.opt.shiftwidth = 4             -- Size of an indent
vim.opt.expandtab = true           -- Use spaces instead of tabs
vim.opt.smartindent = true         -- Insert indents automatically

-- Search
vim.opt.hlsearch = true            -- Highlight search results
vim.opt.incsearch = true           -- Show search matches as you type

-- Split behavior
vim.opt.splitbelow = true          -- Put new windows below current
vim.opt.splitright = true          -- Put new windows right of current

-- Backup and swap
vim.opt.backup = false             -- Don't create backup files
vim.opt.writebackup = false        -- Don't create backup before overwriting
vim.opt.swapfile = false           -- Don't create swap files

-- Key mappings
vim.g.mapleader = ' '              -- Set leader key to space
vim.g.maplocalleader = ' '         -- Set local leader key to space

-- Basic key mappings
local keymap = vim.keymap.set

-- Clear search highlighting
keymap('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Better window navigation
keymap('n', '<C-h>', '<C-w>h', { desc = 'Move to left window' })
keymap('n', '<C-j>', '<C-w>j', { desc = 'Move to bottom window' })
keymap('n', '<C-k>', '<C-w>k', { desc = 'Move to top window' })
keymap('n', '<C-l>', '<C-w>l', { desc = 'Move to right window' })

-- Resize windows
keymap('n', '<C-Up>', '<cmd>resize +2<CR>', { desc = 'Increase window height' })
keymap('n', '<C-Down>', '<cmd>resize -2<CR>', { desc = 'Decrease window height' })
keymap('n', '<C-Left>', '<cmd>vertical resize -2<CR>', { desc = 'Decrease window width' })
keymap('n', '<C-Right>', '<cmd>vertical resize +2<CR>', { desc = 'Increase window width' })

-- Buffer navigation
keymap('n', '<S-h>', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
keymap('n', '<S-l>', '<cmd>bnext<CR>', { desc = 'Next buffer' })

-- Better indenting
keymap('v', '<', '<gv', { desc = 'Indent left' })
keymap('v', '>', '>gv', { desc = 'Indent right' })

-- Move text up and down
keymap('v', 'J', ":m '>+1<CR>gv=gv", { desc = 'Move text down' })
keymap('v', 'K', ":m '<-2<CR>gv=gv", { desc = 'Move text up' })

-- Keep cursor centered when scrolling
keymap('n', '<C-d>', '<C-d>zz', { desc = 'Scroll down and center' })
keymap('n', '<C-u>', '<C-u>zz', { desc = 'Scroll up and center' })

-- Keep search terms in the middle
keymap('n', 'n', 'nzzzv', { desc = 'Next search result' })
keymap('n', 'N', 'Nzzzv', { desc = 'Previous search result' })

-- File operations
keymap('n', '<leader>w', '<cmd>write<CR>', { desc = 'Save file' })
keymap('n', '<leader>q', '<cmd>quit<CR>', { desc = 'Quit' })
keymap('n', '<leader>x', '<cmd>bdelete<CR>', { desc = 'Close buffer' })

-- Quick fix list
keymap('n', '<leader>co', '<cmd>copen<CR>', { desc = 'Open quickfix list' })
keymap('n', '<leader>cc', '<cmd>cclose<CR>', { desc = 'Close quickfix list' })
keymap('n', '<leader>cn', '<cmd>cnext<CR>', { desc = 'Next quickfix item' })
keymap('n', '<leader>cp', '<cmd>cprev<CR>', { desc = 'Previous quickfix item' })

-- Autocommands
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank
augroup('YankHighlight', { clear = true })
autocmd('TextYankPost', {
  group = 'YankHighlight',
  callback = function()
    vim.highlight.on_yank({ higroup = 'IncSearch', timeout = 200 })
  end,
})

-- Remove trailing whitespace on save
augroup('TrimWhitespace', { clear = true })
autocmd('BufWritePre', {
  group = 'TrimWhitespace',
  pattern = '*',
  command = '%s/\\s\\+$//e',
})

-- Auto-create directories when saving files
augroup('AutoCreateDir', { clear = true })
autocmd('BufWritePre', {
  group = 'AutoCreateDir',
  callback = function(event)
    if event.match:match('^%w%w+://') then
      return
    end
    local file = vim.loop.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ':p:h'), 'p')
  end,
})

-- Set filetype-specific settings
augroup('FileTypeSettings', { clear = true })
autocmd('FileType', {
  group = 'FileTypeSettings',
  pattern = { 'lua', 'vim' },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
  end,
})

autocmd('FileType', {
  group = 'FileTypeSettings',
  pattern = { 'yaml', 'yml', 'json' },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
  end,
})

-- Basic colorscheme (fallback)
vim.cmd.colorscheme('default')

-- Status line (simple)
vim.opt.laststatus = 2
vim.opt.statusline = '%f %h%m%r%=%-14.(%l,%c%V%) %P'

print("Neovim configuration loaded successfully!")