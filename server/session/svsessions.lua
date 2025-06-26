--
-- Server Session Handler
--

local log         = require("cb-common.log")
local mqueue      = require("cb-common.mqueue")
local types       = require("cb-common.types")
local util        = require("cb-common.util")

local databus     = require("server.databus")

local pgi         = require("server.panel.pgi")

local client      = require("server.session.client")

local svsessions = {}

---@enum SESSION_TYPE
local SESSION_TYPE = {
    CLI_SESSION = 1
}

svsessions.SESSION_TYPE = SESSION_TYPE

local self = {
    -- references to server state and other data
    nic = nil, ---@type nic|nil
    fp_ok = false,
    config = nil, ---@type svr_config
    --lists of connected sessions
---@diagnostic disable: missing-fields
    sessions = {
        cli = {}, ---@type cli_session_struct
    },
---@diagnostic enable: missing-fields
    -- next session IDs
    next_ids = { cli = 0 }
}

---@alias sv_session_structs cli_session_struct

--#region PRIVATE FUNCTIONS

-- handle a session output queue
---@param session sv_session_structs
local function _sv_handle_outq(session)
    -- record handler start time
    local handle_start = util.time()

    -- process output queue
    while session.out_queue.ready() do
        -- get a new message to process
        local msg = session.out_queue.pop()

        if msg ~= nil then
            if msg.qtype == mqueue.TYPE.PACKET then
                -- handle a packet to be sent
                self.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
            elseif msg.qtype == mqueue.TYPE.COMMAND then
                -- handle instruction/notification
            elseif msg.qtype == mqueue.TYPE.DATA then
                -- instruction/notification with body
                local cmd = msg.message ---@type queue_data
            end
        end

        -- max 100ms spent processing queue
        if util.time() - handle_start > 100 then
            log.debug("SVS: server out queue handler exceeded 100ms queue process limit")
            log.debug(util.c("SVS: offending session: ", session))
            break
        end
    end
end

-- iterate all the given sessions
---@param sessions sv_session_structs[]
local function _iterate(sessions)
    for i = 1, #sessions do
        local session = sessions[i]

        if session.open and session.instance.iterate() then
            _sv_handle_outq(session)
        else
            session.open = false
        end
    end
end

-- cleanly close a session
---@param session sv_session_structs
local function _shutdown(session)
    session.open = false
    session.instance.close()

    -- send packets in out queue (for the close packet)
    while session.out_queue.ready() do
        local msg = session.out_queue.pop()
        if msg ~= nil and msg.qtype == mqueue.TYPE.PACKET then
            self.nic.transmit(session.r_chan, self.config.SVR_Channel, msg.message)
        end
    end

    log.debug(util.c("SVS: closed session ", session))
end

-- close connections
---@param sessions sv_session_structs[]
local function _close(sessions)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then _shutdown(sessions) end
    end
end

-- check if a watchdog timer event matches that of one of the provided sessions
---@param sessions sv_session_structs[]
---@param timer_event number
local function _check_watchdogs(sessions, timer_event)
    for i = 1, #sessions do
        local session = sessions[i]
        if session.open then
            local triggered = session.instance.check_wd(timer_event)
            if triggered then
                log.debug(util.c("SVS: watchdog closing session ", session, "..."))
                _shutdown(session)
            end
        end
    end
end

-- delete any closed sessions
---@param sessions sv_session_structs[]
local function _free_closed(sessions)
    ---@param session sv_session_structs
    local f = function (session) return session.open end

    ---@param session sv_session_structs
    local on_delete = function (session)
        log.debug(util.c("SVS: free'ing closed session ", session))
    end

    util.filter_table(sessions, f, on_delete)
end

-- find a session by computer ID
---@nodiscard
---@param list sv_session_structs[]
---@param s_addr integer
---@return sv_session_structs|nil
local function _find_session(list, s_addr)
    for i = 1, #list do
        if list[i].s_addr == s_addr then return list[i] end
    end
    return nil
end

-- initalize svsessions
---@param nic nic network interface device
---@param fp_ok boolean front panel active
---@param config svr_config server configuration
function svsessions.init(nic, fp_ok, config)
    self.nic = nic
    self.fp_ok = fp_ok
    self.config = config
end

-- find an CLI session by computer ID
---@nodiscard
---@param source_addr integer
---@return cli_session_struct|nil
function svsessions.find_cli_session(source_addr)
    -- check CLI sessions
    local session = _find_session(self.sessions.cli, source_addr)
    ---@cast session cli_session_struct|nil
    return session
end

-- establish a new CLI session
---@nodiscard
---@param source_addr integer CLI computer ID
---@param i_seq_num integer initial (most recent) sequence number
---@param version string CLI version
---@return integer|false session ID
function svsessions.establish_cli_session(source_addr, i_seq_num, version)
    if svsessions.find_cli_session(source_addr) == nil and source_addr >= 1 then
        ---@class cli_session_struct
        local cli_s = {
            s_type = "cli",
            open = true,
            version = version,
            r_chan = self.config.CLI_Channel,
            s_addr = source_addr,
            in_queue = mqueue.new(),
            out_queue = mqueue.new(),
            instance = nil, ---@type cli_session
        }

        local id = self.next_ids.cli

        cli_s.instance = client.new_session(id, source_addr, i_seq_num, cli_s.in_queue, cli_s.out_queue, self.config.CLI_Timeout, self.fp_ok)
        table.insert(self.sessions.cli, cli_s)

        local mt = {
            ---@param s cli_session_struct
            __tostring = function (s) return util.c("CLI [", s.instance.get_id(), "]") end
        }

        setmetatable(cli_s, mt)

        databus.tx_cli_connected(version, source_addr)
        log.debug(util.c("SVS: established new session: ", cli_s))

        self.next_ids.cli = id + 1

        -- success
        return cli_s.instance.get_id()
    else
        -- client connection already established
        return false
    end
end

-- attempt to identify which session's watchdog timer fired
---@param timer_event number
function svsessions.check_all_watchdogs(timer_event)
    for _, list in pairs(self.sessions) do _check_watchdogs(list, timer_event) end
end

-- iterate all sessions, and update data & process control logic
function svsessions.iterate_all()
    -- iterate sessions
    for _, list in pairs(self.sessions) do _iterate(list) end
end

-- delete all closed sessions
function svsessions.free_all_closed()
    for _, list in pairs(self.sessions) do _free_closed(list) end
end

-- close all open connections
function svsessions.close_all()
    -- close sessions
    for _, list in pairs(self.sessions) do _close(list) end

    -- free sessions
    svsessions.free_all_closed()
end

--#endregion

return svsessions