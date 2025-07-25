local comms = require "cb-common.comms"
local log = require "cb-common.log"
local mqueue = require "cb-common.mqueue"
local util = require "cb-common.util"
local databus = require "server.databus"

local client = {}

local PROTOCOL = comms.PROTOCOL
local CLI_TYPES = comms.CLI_TYPES

-- retry time constants in ms
-- local INITIAL_WAIT = 1500
-- local RETRY_PERIOD = 1000

local CLIENT_S_CMDS = {}

local CLIENT_S_DATA = {}

client.CLIENT_S_CMDS = CLIENT_S_CMDS
client.CLIENT_S_DATA = CLIENT_S_DATA

local PERIODICS = {
    KEEP_ALIVE = 2000
}

-- client session
---@param id integer session ID
---@param s_addr integer device source address
---@param i_seq_num integer initial sequence number
---@param in_queue mqueue in message queue
---@param out_queue mqueue out message queue
---@param timeout number communications timeout
---@param fp_ok boolean if the front panel UI is running
function client.new_session(id, s_addr, i_seq_num, in_queue, out_queue, timeout, fp_ok)
    -- print a log message to the terminal as long as the UI isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local log_tag = "cli_session(" .. id .. "): "

    local self = {
        -- connection properties
        seq_num = i_seq_num + 2, -- next after the establish approval was sent
        r_seq_num = i_seq_num + 1,
        connected = true,
        conn_watchdog = util.new_watchdog(timeout),
        last_rtt = 0,
        -- periodic messages
        periodics = {
            last_update = 0,
            keep_alive = 0
        },
        -- when to next retry one of these requests
        retry_times = {},
        -- command acknowledgements
        acks = {},
        -- session database
        ---@class cli_db
        sDB = {}
    }

    ---@class cli_session
    local public = {}

    -- mark this session as closed, stop watchdog
    local function _close()
        self.conn_watchdog.cancel()
        self.connected = false
        databus.tx_cli_disconnected(id)
    end

    -- send a client packet
    ---@param msg_type CLI_TYPES
    ---@param msg table
    local function _send_cli(msg_type, msg)
        local s_pkt = comms.packet()
        local c_pkt = comms.cli_packet()

        c_pkt.make(msg_type, msg)
        s_pkt.make(s_addr, self.seq_num, PROTOCOL.C_PROTO, c_pkt.raw_sendable())

        out_queue.push_packet(s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- handle a packet
    ---@param pkt cli_frame
    local function _handle_packet(pkt)
        -- check sequence number
        if self.r_seq_num ~= pkt.frame.seq_num() then
            log.warning(log_tag .. "sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. pkt.frame.seq_num())
            return
        else
            self.r_seq_num = pkt.frame.seq_num() + 1
        end

        -- feed watchdog
        self.conn_watchdog.feed()

        -- process packet
        if pkt.frame.protocol() == PROTOCOL.C_PROTO then
            ---@cast pkt cli_frame
            if pkt.type == CLI_TYPES.KEEP_ALIVE then
                -- keep alive reply
                if pkt.length == 2 then
                    local srv_start = pkt.data[1]
                    local srv_now = util.time()
                    self.last_rtt = srv_now - srv_start

                    if self.last_rtt > 750 then
                        log.warning(log_tag .. "CLI KEEP_ALIVE round trip time > 750ms (" .. self.last_rtt .. "ms)")
                    end

                    databus.tx_cli_rtt(id, self.last_rtt)
                else
                    log.debug(log_tag .. " keep alive packet length mismatch")
                end
            elseif pkt.type == CLI_TYPES.CLOSE then
                -- close the session
                _close()
            elseif pkt.type == CLI_TYPES.ESTABLISH then
                -- something is wrong, kill the session
                _close()
                log.warning(log_tag .. "terminated session due to unexpected ESTABLISH packet")
            else
                log.debug(log_tag .. "handler received unsupported C_PROTO packet type " .. pkt.type)
            end
        end
    end

    -- PUBLIC FUNCTIONS --

    -- get the session ID
    ---@nodiscard
    function public.get_id() return id end

    -- get the session database
    ---@nodiscard
    function public.get_db() return self.sDB end

    -- check if a timer matches this session's watchdog
    ---@nodiscard
    function public.check_wd(timer)
        return self.conn_watchdog.is_timer(timer) and self.connected
    end

    -- close the connection
    function public.close()
        _close()
        _send_cli(CLI_TYPES.CLOSE, {})
        println("connection to client session " .. id .. " closed by server")
        log.info(log_tag .. "session closed by server")
    end

    -- iterate the session
    ---@nodiscard
    ---@return boolean connected
    function public.iterate()
        if self.connected then
            ------------------
            -- handle queue --
            ------------------
            
            local handle_start = util.time()

            while in_queue.ready() and self.connected do
                -- get a new message to process
                local message = in_queue.pop()

                if message ~= nil then
                    if message.qtype == mqueue.TYPE.PACKET then
                        -- handle a packet
                        _handle_packet(message.message)
                    elseif message.qtype == mqueue.TYPE.COMMAND then
                        -- handle instruction
                    elseif message.qtype == mqueue.TYPE.DATA then
                        -- instruction with body
                    end
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log.warning(log_tag .. "exceeded 100m queue process limit")
                    break
                end
            end

            -- exit if connection closed

            if not self.connected then
                println("connection to client session " .. id .. " closed by remote host")
                log.info(log_tag .. "session closed by remote host")
                return self.connected
            end

            ----------------------
            -- update periodics --
            ----------------------
            
            local elapsed = util.time() - self.periodics.last_update

            local periodics = self.periodics

            -- keep alive

            periodics.keep_alive = periodics.keep_alive + elapsed
            if periodics.keep_alive >= PERIODICS.KEEP_ALIVE then
                _send_cli(CLI_TYPES.KEEP_ALIVE, { util.time() })
                periodics.keep_alive = 0
            end

            self.periodics.last_update = util.time()

            ---------------------
            -- attempt retries --
            ---------------------
            
            -- local rtimes = self.retry_times
        end

        return self.connected
    end

    return public
end

return client