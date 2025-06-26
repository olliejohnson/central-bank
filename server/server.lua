local log = require "cb-common.log"
local util = require "cb-common.util"

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

return server