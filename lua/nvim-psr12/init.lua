
local M = {}

-- Private functions
local function create_diagnostics_from_phpcs(results)
    local current_file = vim.fn.expand('%:p')
    vim.diagnostic.reset(vim.api.nvim_create_namespace('phpcs'))

    local diagnostics = {}
    for _, item in ipairs(results) do
        if item.filename == current_file then
            table.insert(diagnostics, {
                lnum = item.lnum - 1,
                col = item.col - 1,
                end_lnum = item.lnum - 1,
                end_col = item.col,
                severity = item.type == "error" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
                message = item.text,
                source = "phpcs"
            })
        end
    end

    vim.diagnostic.set(vim.api.nvim_create_namespace('phpcs'), 0, diagnostics)
end

local function parse_phpcs_output(output)
    local results = {}
        -- Matches PHP_CodeSniffer output in format: "file:line:column: type - message"
        -- ([^:]+)   - Captures filename (any chars except colon)
        -- (%d+)     - Captures line number (digits)
        -- (%d+)     - Captures column number (digits)
        -- (%w+)     - Captures type (word chars like "ERROR" or "WARNING")
        -- (.+)      - Captures the message (rest of the line after " - ")
    for line in output:gmatch("[^\r\n]+") do
        local file, lnum, col, type, msg = line:match("([^:]+):(%d+):(%d+): (%w+) %- (.+)")
        if file and lnum and col and type and msg then
            table.insert(results, {
                filename = file,
                lnum = tonumber(lnum),
                col = tonumber(col),
                type = type,
                text = msg
            })
        end
    end
    return results
end

local function check_current_file()
    local current_file = vim.fn.expand('%:p')
    if current_file == "" then
        print("No file is currently open")
        return {}
    end
    if not current_file:match("%.php$") then
        print("Not a PHP file")
        return {}
    end

    return current_file
end

local function get_phpcs_output(current_file)
    local output = vim.fn.system(string.format("phpcs --standard=PSR12 -q --report=emacs %s", vim.fn.shellescape(current_file)))
    return output
end

local function construct_diagnostics(results)
    create_diagnostics_from_phpcs(results)
    return results
end

local function run_phpcs_diagnostics()
    local current_file = check_current_file()
    if not current_file then return {} end

    local output = get_phpcs_output(current_file)
    if output == "" then
        return {}
    end

    local parsed_output = parse_phpcs_output(output)
    return construct_diagnostics(parsed_output)
end

-- Create telescope picker
local function create_telescope_picker(results)
    if #results > 0 then
        require('telescope.pickers').new({}, {
            prompt_title = "PHP CodeSniffer Results",
            finder = require('telescope.finders').new_table {
                results = results,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = string.format("%s: %s (%s:%d:%d)",
                            entry.type,
                            entry.text,
                            vim.fn.fnamemodify(entry.filename, ":t"),
                            entry.lnum,
                            entry.col
                        ),
                        ordinal = entry.filename .. entry.text,
                        filename = entry.filename,
                        lnum = entry.lnum,
                        col = entry.col,
                    }
                end,
            },
            sorter = require('telescope.config').values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
                require('telescope.actions').select_default:replace(function()
                    require('telescope.actions').close(prompt_bufnr)
                    local selection = require('telescope.actions.state').get_selected_entry()
                    vim.cmd(string.format("edit +%d %s", selection.lnum, selection.filename))
                    vim.api.nvim_win_set_cursor(0, {selection.lnum, selection.col - 1})
                end)
                return true
            end,
        }):find()
    end
end

-- Public function to manually check file
M.check = function()
    local results = run_phpcs_diagnostics()
    create_telescope_picker(results)
end

-- Setup function
M.setup = function(opts)
    opts = opts or {}
    
    -- Create autocommand group
    M.augroup = vim.api.nvim_create_augroup("phpcs_check", { clear = true })

    -- Add autocmd to check on save
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = M.augroup,
        pattern = "*.php",
        callback = function()
            run_phpcs_diagnostics()
        end,
    })

    -- Create user command
    vim.api.nvim_create_user_command("PhpcsCheck", function()
        M.check()
    end, {})

    -- Set up keymapping if not disabled
    if opts.enable_keymaps ~= false then
        vim.keymap.set('n', '<leader>pc', ':PhpcsCheck<CR>', { 
            desc = 'PHP CodeSniffer check',
            noremap = true,
            silent = true
        })
    end
end

return M
