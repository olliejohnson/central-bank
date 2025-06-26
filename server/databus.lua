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
function databus.tx_versions(sv_v)
    databus.ps.publish("version", sv_v)
end

-- transmit hardware status for modem connection state
---@param has_modem boolean
function databus.tx_hw_modem(has_modem)
    databus.ps.publish("has_modem", has_modem)
end

-- link a function to receive data from the bus
---@param field string field name
---@param func function function to link
function databus.rx_field(field, func)
    databus.ps.subscribe(field, func)
end

return databus