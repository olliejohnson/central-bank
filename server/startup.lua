require("/initenv").init_env()
local network = require("cb-common.network")
local svsessions = require("server.session.svsessions")

local crash = require "cb-common.crash"
local log = require "cb-common.log"
local ppm = require "cb-common.ppm"
local tcd = require "cb-common.tcd"
local types = require "cb-common.types"
local util = require "cb-common.util"

local core = require "graphics.core"

local databus = require "server.databus"
local configure = require "server.configure"
local server = require "server.server"
local renderer = require "server.renderer"

---@diagnostic disable-next-line:unused-local
local SERVER_VERSION = "v0.0.0.1-alpha"

local println = util.println
local println_ts = util.print_ts

-- get configuration

if not server.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not server.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: "..error)
        return
    end
end

local config = server.config

-- log init

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING server.startup " .. SERVER_VERSION)
log.info("========================================")
println(">> Central Bank Server " .. SERVER_VERSION .. " <<")

crash.set_env("server", SERVER_VERSION)
crash.dbg_log_env()

-- main application

local function main()
    -- startup
    databus.tx_versions(SERVER_VERSION)

    -- mount connected devices
    ppm.mount_all()

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    -- get modem
    local modem = ppm.get_wireless_modem()
    if modem == nil then
        println("startup> wireless modem not found")
        log.fatal("no wireless modem on startup")
        return
    end

    databus.tx_hw_modem(true)

    -- start UI
    local fp_ok, message = renderer.try_start_ui(config.FrontPanelTheme, config.ColorMode)

    if not fp_ok then
        println_ts(util.c("UI error: ", message))
        log.error(util.c("front panel GUI render failed with error ", message))
    else
        -- redefine println_ts local to not print as we have the front panel running
        println_ts = function(_) end
    end

    -- create network interface then setup comms
    local nic = network.nic(modem)
    local server_comms = server.comms(SERVER_VERSION, nic, fp_ok)

    -- base loop clock (6.67hz, 3 ticks)
    local MAIN_CLOCK = 0.15
    local loop_clock = util.new_clock(MAIN_CLOCK)

    -- start clock
    loop_clock.start()

    -- halve the rate heartbeat LED flash
    local heartbeat_toggle = true

    -- event loop
    while true do
        local event, param1, param2, param3, param4, param5 = util.pull_event()

        -- handle event
        if event == "peripheral_detach" then
            local type, device = ppm.handle_unmount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    ---@cast device Modem
                    -- we only care if this is our wireless modem
                    if nic.is_modem(device) then
                        nic.disconnect()

                        println_ts("wireless modem disconnected!")
                        log.warning("comms modem diconnected")

                        local other_modem = ppm.get_wireless_modem()
                        if other_modem then
                            log.info("found another wireless modem, using it for comms")
                            nic.connect(other_modem)
                        else
                            databus.tx_hw_modem(false)
                        end
                    end
                else
                    log.warning("non-comms modem disconnected")
                end
            end
        elseif event == "peripheral" then
            local type, device = ppm.mount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    ---@cast device Modem
                    if device.isWireless() and not nic.is_connected() then
                        -- reconnected modem
                        nic.connect(device)

                        println_ts("wireless modem reconnected.")
                        log.info("comms modem reconnected")

                        databus.tx_hw_modem(true)
                    elseif device.isWireless() then
                        log.info("unused wireless modem reconnected")
                    else
                        log.info("wired modem reconnected")
                    end
                end
            end
        elseif event == "timer" and loop_clock.is_clock(param1) then
            -- main loop tick

            if heartbeat_toggle then databus.heartbeat() end
            heartbeat_toggle = not heartbeat_toggle

            loop_clock.start()
        elseif event == "timer" then
            -- a non-clock timer event, check watchdogs
            svsessions.check_all_watchdogs(param1)

            -- notify timer callback dispatcher
            tcd.handle(param1)
        elseif event == "modem_message" then
            -- got a packet
            local packet = server_comms.parse_packet(param1, param2, param3, param4, param5)
            if packet then server_comms.handle_packet(packet) end
        elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
            renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
        end

        -- check for termination request
        if event == "terminate" or ppm.should_terminate() then
            println_ts("closing sessions...")
            log.info("terminate requested, closing session...")
            svsessions.close_all()
            log.info("sessions closed")
            break
        end
    end

    renderer.close_ui()

    util.print_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end