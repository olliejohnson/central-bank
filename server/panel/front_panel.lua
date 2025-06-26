--
-- Server Front Panel GUI
--

local util = require "cb-common.util"

local databus = require("server.databus")
local server = require "server.server"

local pgi = require "server.panel.pgi"
local style = require "server.panel.style"

local account_entry = require "server.panel.components.account_entry"

local core          = require("graphics.core")

local Div           = require("graphics.elements.Div")
local ListBox       = require("graphics.elements.ListBox")
local MultiPane     = require("graphics.elements.MultiPane")
local TextBox       = require("graphics.elements.TextBox")

local TabBar        = require("graphics.elements.controls.TabBar")

local LED           = require("graphics.elements.indicators.LED")
local DataIndicator = require("graphics.elements.indicators.DataIndicator")

local ALIGN = core.ALIGN

local cpair = core.cpair

local ind_grn = style.ind_grn

-- create new front panel view
---@param panel DisplayBox main displaybox
local function init(panel)
    local s_hi_box = style.theme.highlight_box
    local s_hi_bright = style.theme.highlight_box_bright

    local label_fg = style.fp.label_fg
    local label_d_fg = style.fp.label_d_fg

    local term_w, term_h = term.getSize()

    TextBox{parent=panel, y=1, text="Central Bank Supervisor", alignment=ALIGN.CENTER, fg_bg=style.theme.header}

    local page_div = Div{parent=panel, x=1, y=3}

    --
    -- system indicators
    --

    local main_page = Div{parent=page_div, x=1, y=1}

    local system = Div{parent=main_page, width=14, height=17, x=2, y=2}

    local on = LED{parent=system, label="STATUS", colors=cpair(colors.green, colors.red)}
    local heartbeat = LED{parent=system, label="HEARTBEAT", colors=ind_grn}
    on.update(true)
    system.line_break()

    heartbeat.register(databus.ps, "heartbeat", heartbeat.update)

    local modem = LED{parent=system, label="MODEM", colors=ind_grn}
    system.line_break()

    modem.register(databus.ps, "has_modem", modem.update)

---@diagnostic disable-next-line: undefined-field
    local comp_id = util.sprintf("(%d)", os.getComputerID())
    TextBox{parent=system, x=9, y=4, width=6, text=comp_id, fg_bg=style.fp.disabled_fg}

    --
    -- about footer
    --

    local about = Div{parent=main_page, width=15, height=2, y=term_h-3, fg_bg=style.fp.disabled_fg}
    local fw_v = TextBox{parent=about, text="FW: v00.00.00"}
    local comms_v = TextBox{parent=about, text="NT: v00.00.00"}

    fw_v.register(databus.ps, "version", function (version) fw_v.set_value(util.c("FW: ", version)) end)
    comms_v.register(databus.ps, "comms_version", function (version) comms_v.set_value(util.c("NT: v", version)) end)

    --
    -- page handling
    --

    -- accounts page

    local accounts_page = Div{parent=page_div, x=1, y=1, hidden=true}
    local account_list = ListBox{parent=accounts_page, x=2, y=2, width=term_w-2, scroll_height=1000, fg_bg=style.fp.text_fg, nav_fg_bg=cpair(colors.gray,colors.lightGray), nav_active=cpair(colors.black, colors.gray)}
    local _ = Div{parent=account_list,height=1}

    -- info page

    local info_page = Div{parent=page_div, y=1, hidden=true}
    local info = Div{parent=info_page, height=6, x=2, y=2}

    TextBox{parent=info, text="SVR \x1a Server Status"}
    TextBox{parent=info, text="CLI \x1a Client Connections"}

    -- assemble page_div panes

    local panes = { main_page, accounts_page, info_page }

    local page_pane = MultiPane{parent=page_div, x=1, y=1, panes=panes}

    local tabs = {
        { name = "SVR", color = style.fp.text },
        { name = "ACC", color = style.fp.text },
        { name = "INF", color = style.fp.text }
    }

    TabBar{parent=panel, y=2, tabs=tabs, min_width=7, callback=page_pane.set_value, fg_bg=style.theme.highlight_box_bright}

    pgi.link_elements(account_list, account_entry)
end

return init