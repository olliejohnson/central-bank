require("/initenv").init_env()

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
local SERVER_VERSION = "v0.0.2-alpha"

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
                    databus.tx_hw_modem(false)
                end
            end
        elseif event == "peripheral" then
            local type, device = ppm.mount(param1)

            if type ~= nil and device ~= nil then
                if type == "modem" then
                    ---@cast device Modem
                    if device.isWireless() then
                        databus.tx_hw_modem(true)
                    end
                end
            end
        elseif event == "timer" and loop_clock.is_clock(param1) then
            -- main loop tick

            if heartbeat_toggle then databus.heartbeat() end
            heartbeat_toggle = not heartbeat_toggle

            loop_clock.start()
        elseif event == "timer" then
            tcd.handle(param1)
        elseif event == "modem_message" then
            -- got a packet
        elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
            renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
        end

        -- check for termination request
        if event == "terminate" or ppm.should_terminate() then
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