local log = require "cb-common.log"
local util = require "cb-common.util"
local comms = require "cb-common.comms"
local svsessions = require "server.session.svsessions"

local themes = require "graphics.themes"

local server = {}

---@type svr_config
---@diagnostic disable-next-line: missing-fields
local config = {}

server.config = config

-- control state from last unexpected shutdown
server.boot_state = nil ---@type sv_boot_state|nil

-- load the server configuration and startup state
function server.load_config()
    if not settings.load("/server.settings") then return false end

    ---@class sv_boot_state
    local boot_state = {
        mode = settings.get("LastProcessState"),
    }

    -- only record boot state if likely valid
    if type(boot_state.mode) == "number" then
        server.boot_state = boot_state
    end

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    local cfv = util.new_validator()

    cfv.assert_type_int(config.LogMode)
    cfv.assert_range(config.LogMode, 0, 1)
    cfv.assert_type_str(config.LogPath)
    cfv.assert_type_bool(config.LogDebug)

    cfv.assert_type_int(config.FrontPanelTheme)
    cfv.assert_range(config.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(config.ColorMode)
    cfv.assert_range(config.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    return cfv.valid()
end

-- server communications
---@nodiscard
---@param _version string server version
---@param nic nic network interface device
---@param fp_ok boolean if the front panel UI is running
function server.comms(_version, nic, fp_ok)
    -- print a log message to the terminal as long as the ui isn't running
    local function println(message) if not fp_ok then util.println_ts(message) end end

    local self = {
        last_est_acks = {}
    }

    comms.set_trused_range(config.TrustedRange)

    -- PRIVATE FUNCTIONS --

    -- configure modem channels
    nic.closeAll()
    nic.open(config.SVR_Channel)

    -- pass system data and objects to svsessions
    svsessions.init(nic, fp_ok, config)

    -- send an establish request response
    ---@param packet packet
    ---@param ack ESTABLISH_ACK
    ---@param data? any optional data
    local function _send_establish(packet, ack, data)
        local s_pkt = comms.packet()
        local c_pkt = comms.cli_packet()

        c_pkt.make(CLi_TYPES.ESTABLISH, { ack, data })
        s_pkt.make(packet.src_addr(), packet.seq_num() + 1, PROTOCOL.C_PROTO, c_pkt.raw_sendable())

        nic.transmit(packet.remote_channel(), config.SVR_Channel, s_pkt)
        self.last_est_acks[packet.src_addr()] = ack
    end

    -- PUBLIC FUNCTIONS --

    ---@class server_comms
    local public = {}

    -- parse a packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return cli_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local s_pkt = nic.receive(side, sender, reply_to, message, distance)
        local pkt = nil

        if s_pkt then
            -- get C Packet
            if s_pkt.protocol() == PROTOCOL.C_PROTO then
                local cli_pkt = comms.cli_packet()
                if cli_pkt.decode(s_pkt) then
                    pkt = cli_pkt.get()
                end
            else
                log.debug("attempted parse of illegal packet type " .. s_pkt.protocol(), true)
            end
        end
        
        return pkt
    end

    -- handle a packet
    ---@param packet cli_frame
    function public.handle_packet(packet)
        local l_chan = packet.frame.local_channel()
        local r_chan = packet.frame.remote_channel()
        local src_addr = packet.frame.src_addr()
        local protocol = packet.frame.protocol()
        local i_seq_num = packet.frame.seq_num()

        if l_chan ~= config.SVR_Channel then
            log.debug("received packet on unconfigured channel " .. l_chan, true)
        elseif r_chan == config.CLI_Channel then
            -- look for an associated session
            local session = svsessions.find_cli_session(src_addr)

            if protocol == PROTOCOL.C_PROTO then
                ---@cast packet cli_frame
                -- client packet
                if session ~= nil then
                    -- pass the packet onto the session handler
                    session.in_queue.push_packet(packet)
                elseif packet.type == CLI_TYPES.ESTABLISH then
                    -- establish a new session
                    local last_ack = self.last_est_acks[src_addr]

                    -- validate packet and continue
                    if packet.length >= 3 and type(packet.data[1]) == "string" and type(packet.data[2]) == "string" then
                        local comms_v = packet.data[1]
                        local firmware_v = packet.data[2]
                        local dev_type = packet.data[3]

                        if comms_v ~= comms.version then
                            if last_ack ~= ESTABLISH_ACK.BAD_VERSION then
                                log.info(util.c("dropping CLI establish packet with incorrect comms version v", comms_v, " (expected v", comms.version, ")"))
                            end

                            _send_establish(packet.frame, ESTABLISH_ACK.BAD_VERSION)
                        elseif dev_type == DEVICE_TYPE.CLI then
                            -- CLI linking request
                            if packet.length == 3 then
                                local cli_id = svsessions.establish_cli_session(src_addr, i_seq_num, firmware_v)

                                if cli_id == false then
                                    -- already established
                                    if last_ack ~= ESTABLISH_ACK.COLLISION then
                                        log.warning(util.c("CLI_ESTABLISH: assignment collision"))
                                    end

                                    _send_establish(packet.frame, ESTABLISH_ACK.COLLISION)
                                else
                                    -- got an ID
                                    println(util.c("CLI (", firmware_v, ") [@", src_addr, "] connected"))
                                    log.info(util.c("CLI_ESTABLISH: CLI (", firmware_v, ") [@", src_addr, "] connected with session ID ", cli_id))
                                    _send_establish(packet.frame, ESTABLISH_ACK.ALLOW)
                                end
                            end
                        else
                            log.debug(util.c("illegal establish packet for device ", dev_type, " on CLI channel"))
                            _send_establish(packet.frame, ESTABLISH_ACK.DENY)
                        end
                    else
                        log.debug("invalid establish packet (on CLI channel)")
                        _send_establish(packet.frame, ESTABLISH_ACK.DENY)
                    end
                else
                    -- any other packet onto the server related, discard it
                    log.debug("discarding CLI packet without a known session")
                end
            else
                log.debug(util.c("illegal packet type ", protocol, " on CLI channel"))
            end
        else
            log.debug("received packet for unknown channel " .. r_chan, true)
        end
    end

    return public
end

return server