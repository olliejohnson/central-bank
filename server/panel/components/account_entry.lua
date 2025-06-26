--
-- Account Status Entry
--

local databus = require "server.databus"

local style = require "server.panel.style"

local core = require "graphics.core"

local Div           = require("graphics.elements.Div")
local TextBox       = require("graphics.elements.TextBox")

local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

local cpair = core.cpair

-- create an account list entry
---@param parent ListBox parent
---@param id integer account id
local function init(parent, id)
    local s_hi_box = style.theme.highlight_box

    local label_fg = style.fp.lable_fg

    local term_w, _ = term.getSize()

    -- root div
    local root = Div{parent=parent,x=2,y=2,height=4,width=parent.get_width()-2}
    local entry = Div{parent=root,x=2,y=1,height=3,fg_bg=style.theme.highlight_box_bright}

    local ps_prefix = "account_"..id.."_"

    TextBox{parent=entry, x=1, y=1, text="", width=8, fg_bg=s_hi_box}
    local account_id = TextBox{parent=entry, x=1, y=2, text="@ C ??", alignment=ALIGN.CENTER, width=8, fg_bg=s_hi_box, nav_active=cpair(colors.gray,colors.black)}
    account_id.register(databus.ps, ps_prefix, account_id.set_value)

    TextBox{parent=entry,x=term_w-15,y=2,text="RTT:",width=4}
    local rtu_rtt = DataIndicator{parent=entry,x=term_w-11,y=2,label="",unit="",format="%5d",value=0,width=5,fg_bg=label_fg}
    TextBox{parent=entry,x=term_w-5,y=2,text="ms",width=4,fg_bg=label_fg}
    rtu_rtt.register(databus.ps, ps_prefix .. "rtt", rtu_rtt.update)
    rtu_rtt.register(databus.ps, ps_prefix .. "rtt_color", rtu_rtt.recolor)

    return root
end

return init