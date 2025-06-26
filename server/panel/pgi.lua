--
-- Protected Graphics Interface
--

local log = require "cb-common.log"
local util = require "cb-common.util"

local pgi = {}

local data = {
    account_list = nil, ---@type ListBox|nil
    account_entry = nil, ---@type function
    -- list entries
    entries = {
        account = {} ---@type Div[]
    }
}

-- link list boxes
---@param account_list ListBox account list element
---@param account_entry fun(parent: ListBox, id: integer): Div account entry constructor
function pgi.link_elements(account_list, account_entry)
    data.account_list = account_list
    data.account_entry = account_entry
end

-- unlink all fields, disabling the PGI
function pgi.unlink()
    data.account_list = nil
    data.account_entry = nil
end

-- add an account entry to the account list
---@param account_id integer account ID
function pgi.create_account_entry(account_id)
    if data.account_list ~= nil and data.account_entry ~= nil then
        local success, result = pcall(data.account_entry, data.account_list, account_id)

        if success then
            data.entries.account[account_id] = result
            log.debug(util.c("PGI: created account entry (", account_id, ")"))
        else
            log.error(util.c("PGI: failed to create account entry (", result, ")"), true)
        end
    end
end

-- delete an account entry from the account list
---@param account_id integer account ID
function pgi.delete_account_entry(account_id)
    if data.entries.account[account_id] ~= nil then
        local success, result = pcall(data.entries.account[account_id].delete)
        data.entries.account[account_id] = nil

        if success then
            log.debug(util.c("PGI: deleted account entry (", account_id, ")"))
        else
            log.error(util.c("PGI: failed to delete account entry (", result, ")"), true)
        end
    else
        log.warning(util.c("PGI: tried to delete unknown account entry ", account_id))
    end
end

return pgi