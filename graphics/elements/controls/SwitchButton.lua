-- Button Graphics Element

local core    = require("graphics.core")
local element = require("graphics.element")

---@class switch_button_args
---@field text string button text
---@field callback function function to call on touch
---@field default? boolean default state, defaults to off (false)
---@field min_width? integer text length + 2 if omitted
---@field active_fg_bg cpair foreground/background colors when pressed
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field height? integer parent height if omitted
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new latching switch button control element.
---@param args switch_button_args
---@return SwitchButton element, element_id id
return function (args)
    element.assert(type(args.text) == "string", "text is a required field")
    element.assert(type(args.callback) == "function", "callback is a required field")
    element.assert(type(args.active_fg_bg) == "table", "active_fg_bg is a required field")
    element.assert(type(args.min_width) == "nil" or (type(args.min_width) == "number" and args.min_width > 0), "min_width must be nil or a number > 0")

    local text_width = string.len(args.text)

    args.height = 1
    args.min_width = args.min_width or 0
    args.width = math.max(text_width, args.min_width)

    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    e.value = args.default or false

    local h_pad = math.floor((e.frame.w - text_width) / 2) + 1
    local v_pad = math.floor(e.frame.h / 2) + 1

    -- show the button state
    function e.redraw()
        if e.value then
            e.w_set_fgd(args.active_fg_bg.fgd)
            e.w_set_bkg(args.active_fg_bg.bkg)
        else
            e.w_set_fgd(e.fg_bg.fgd)
            e.w_set_bkg(e.fg_bg.bkg)
        end

        e.window.clear()
        e.w_set_cur(h_pad, v_pad)
        e.w_write(args.text)
    end

    -- handle mouse interaction
    ---@param event mouse_interaction mouse event
    function e.handle_mouse(event)
        if e.enabled and core.events.was_clicked(event.type) and e.in_frame_bounds(event.current.x, event.current.y) then
            e.value = not e.value
            e.redraw()
            args.callback(e.value)
        end
    end

    -- set the value (does not call the callback)
    ---@param val boolean new value
    function e.set_value(val)
        e.value = val
        e.redraw()
    end

    ---@class SwitchButton:graphics_element
    local SwitchButton, id = e.complete(true)

    return SwitchButton, id
end