--
-- Data Bus - Central Communication Linking for Server Front Panel
--

local psil = require "cb-common.psil"
local util = require "cb-common.util"

local pgi = require "server.panel.pgi"

-- nominal RTT is ping (0ms to 10ms usually) + 150ms for SV main loop tick
local WARN_RTT = 300 -- 2x as long as expected w/ 0 ping
local HIGH_RTT = 500 -- 3.33x as long as expected w/ 0 ping

local databus = {}

-- databus PSIL
databus.ps = psil.create()

-- call to toggle heartbeat signal
function databus.heartbeat() databus.ps.toggle("heartbeat") end

-- transmit firmware versions across the bus
---@param sv_v string server version
---@param comms_v string comms version
function databus.tx_versions(sv_v, comms_v)
    databus.ps.publish("version", sv_v)
    databus.ps.publish("comms_version", comms_v)
end

-- transmit hardware status for modem connection state
---@param has_modem boolean
function databus.tx_hw_modem(has_modem)
    databus.ps.publish("has_modem", has_modem)
end

-- transmit CLI firmware version and session connection state
---@param session_id integer CLI session
---@param fw string firmware version
---@param s_addr integer CLI computer ID
function databus.tx_cli_connected(session_id, fw, s_addr)
    databus.ps.publish("cli_" .. session_id .. "_fw", fw)
    databus.ps.publish("cli_" .. session_id .. "_addr", util.sprintf("@ C% 3d", s_addr))
    pgi.create_account_entry(session_id)
end

-- transmit CLI session disconnected
---@param session_id integer CLI session
function databus.tx_cli_disconnected(session_id)
    pgi.delete_account_entry(session_id)
end

-- transmit CLI session RTT
---@param session_id integer CLI session
---@param rtt integer round trip time
function databus.tx_cli_rtt(session_id, rtt)
    databus.ps.publish("cli_" .. session_id .. "_rtt", rtt)

    if rtt > HIGH_RTT then
        databus.ps.publish("cli_" .. session_id .. "_rtt_color", colors.red)
    elseif rtt > WARN_RTT then
        databus.ps.publish("cli_" .. session_id .. "_rtt_color", colors.yellow_hc)
    else
        databus.ps.publish("cli_" .. session_id .. "_rtt_color", colors.green_hc)
    end
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus