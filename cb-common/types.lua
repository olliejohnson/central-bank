--
-- Global Types
--

---@class types
local types = {}

--#region CC: TWEAKED CLASSES https://tweaked.cc

---@class Redirect
---@field write fun(text: string) Write text at the current cursor position, moving the cursor to the end of the text.
---@field scroll fun(y: integer) Move all positions up (or down) by y pixels.
---@field getCursorPos fun() : x: integer, y: integer Get the position of the cursor.
---@field setCursorPos fun(x: integer, y: integer) Set the position of the cursor.
---@field getCursorBlink fun() : boolean Checks if the cursor is currently blinking.
---@field setCursorBlink fun(blink: boolean) Sets whether the cursor should be visible (and blinking) at the current cursor position.
---@field getSize fun() : width: integer, height: integer Get the size of the terminal.
---@field clear fun() Clears the terminal, filling it with the current background color.
---@field clearLine fun() Clears the line the cursor is currently on, filling it with the current background color.
---@field getTextColor fun() : color Return the color that new text will be written as.
---@field setTextColor fun(color: color) Set the colour that new text will be written as.
---@field getBackgroundColor fun() : color Return the current background color.
---@field setBackgroundColor fun(color: color) set the current background color.
---@field isColor fun() Determine if this terminal supports color.
---@field blit fun(text: string, textColor: string, backgroundColor: string) Writes text to the terminal with the specific foreground and background colors.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, color: integer) Set the palette for a specific color.
---@diagnostic disable-next-line: duplicate-doc-field
---@field setPaletteColor fun(index: color, r: number, g: number, b:number) Set the palette for a specific color. R/G/B are 0 to 1.
---@field getPaletteColor fun(color: color) :  r: number, g: number, b:number Get the current palette for a specific color.

---@class Window:Redirect
---@field getLine fun(y: integer) : content: string, fg: string, bg: string Get the buffered contents of a line in this window.
---@field setVisible fun(visible: boolean) Set whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field isVisible fun() : visible: boolean Get whether this window is visible. Invisible windows will not be drawn to the screen until they are made visible again.
---@field redraw fun() Draw this window. This does nothing if the window is not visible.
---@field restoreCursor fun() Set the current terminal's cursor to where this window's cursor is. This does nothing if the window is not visible.
---@field getPosition fun() : x: integer, y: integer Get the position of the top left corner of this window.
---@field reposition fun(new_x: integer, new_y: integer, new_width?: integer, new_height?: integer, new_parent?: Redirect) Reposition or resize the given window.

---@class Monitor:Redirect
---@field setTextScale fun(scale: number) Set the scale of this monitor.
---@field getTextScale fun() : number Get the monitor's current text scale.

---@class Modem
---@field open fun(channel: integer) Open a channel on a modem.
---@field isOpen fun(channel: integer) : boolean Check if a channel is open.
---@field close fun(channel: integer) Close an open channel, meaning it will no longer receive messages.
---@field closeAll fun() Close all open channels.
---@field transmit fun(channel: integer, replyChannel: integer, payload: any) Sends a modem message on a certain channel.
---@field isWireless fun() : boolean Determine if this is a wired or wireless modem.
---@field getNamesRemote fun() : string[] List all remote peripherals on the wired network.
---@field isPresentRemote fun(name: string) : boolean Determine if a peripheral is available on this wired network.
---@field getTypeRemote fun(name: string) : string|nil Get the type of a peripheral is available on this wired network.
---@field hasTypeRemote fun(name: string, type: string) : boolean|nil Check a peripheral is of a particular .
---@field getMethodsRemote fun(name: string) : string[] Get all available methods for the remote peripheral with the given name.
---@field callRemote fun(remoteName: string, method: string, ...) : table Call a method on a peripheral on this wired network.
---@field getNameLocal fun() : string|nil Returns the network name of the current computer, if the modem is on.

---@class Speaker
---@field playNote fun(instrument: string, volume?: number, pitch?: number) : success: boolean Plays a note block note through the speaker.
---@field playSound fun(name: string, volume?: number, pitch?: number) : success: boolean Plays a Minecraft sound through the speaker.
---@field playAudio fun(audio: number[], volume?: number) : success: boolean Attempt to stream some audio data to the speaker.
---@field stop fun() Stop all audio being played by this speaker.

---@class ChatBox
---@field sendMessage fun(message: string, prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: boolean|nil|string
---@field sendMessageToPlayer fun(message: string, username: string, prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: true|nil|string
---@field sendToastToPlayer fun(message: string, title: string, username: string, prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: true|nil|string
---@field sendFormattedMessage fun(message: Message[], prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: true|nil|string
---@field sendFormattedMessageToPlayer fun(message: Message[], username: string, prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: true|nil|string
---@field sendFormattedToastToPlayer fun(message: Message[], title: Message[], username: string, prefix?: string, brackets?: string, bracketColor?: string, range?: number) : status: true|nil|string

--#endregion

--#region CLASSES

---@class Message
---@field text? string
---@field translate? string
---@field fallback? string
---@field with? Message[]
---@field score? {name: string, objective: string}
---@field selector? string
---@field separator? {color?: string, text?: string}
---@field keybind? string
---@field nbt? any
---@field color? string
---@field font? string
---@field bold? boolean
---@field italic? boolean
---@field underlined? boolean
---@field strikethrough? boolean
---@field obfuscated? boolean
---@field shadow_color? number|[number, number, number, number]
---@field insertion? string
---@field click_event? {action: "open_url", url: string}|{action: "open_file", path: string}|{action: "run_command", command: string}|{action: "suggest_command", command: string}|{action: "copy_to_clipboard", value: string}|{action: "show_dialog", dialog: string}|{action: "custom", id: string, payload?: string}
---@field hover_event? {action: "show_text", value: string|Message[]|Message}|{action: "show_item", id: string, count?: number, components?: {}}|{action: "show_entity", name?: Message, id: string, uuid: string|[number, number, number, number]}

---@class coordinate_2d
---@field x integer
---@field y integer

---@class coordinate
---@field x integer
---@field y integer
---@field z integer

-- create a new coordinate
---@nodiscard
---@param x integer
---@param y integer
---@param z integer
---@return coordinate
function types.new_coordinate(x, y, z) return { x = x, y = y, z = z } end

-- create a new zero coordinate
---@nodiscard
---@return coordinate
function types.new_zero_coordinate() return { x = 0, y = 0, z = 0 } end

--#endregion

-- ALIASES --

---@alias color integer

--#region ENUMERATION TYPES

---@enum PANEL_LINK_STATE
types.PANEL_LINK_STATE = {
    LINKED = 1,
    DENIED = 2,
    COLLISION = 3,
    BAD_VERSION = 4,
    DISCONNECTED = 5
}

---@enum TRI_FAIL
types.TRI_FAIL = {
    OK = 1,
    PARTIAL = 2,
    FULL = 3
}

---@enum AUTO_GROUP
types.AUTO_GROUP = {
    MANUAL = 0,
    PRIMARY = 1,
    SECONDARY = 2,
    TERTIARY = 3,
    BACKUP = 4
}

types.AUTO_GROUP_NAMES = {
    "Manual",
    "Primary",
    "Secondary",
    "Tertiary",
    "Backup"
}

--#endregion

--#region STRING TYPES

---@alias side
---|"top"
---|"bottom"
---|"left"
---|"right"
---|"front"
---|"back"

---@alias os_event
---| "alarm"
---| "char"
---| "computer_command"
---| "disk"
---| "disk_eject"
---| "http_check"
---| "http_failure"
---| "http_success"
---| "key"
---| "key_up"
---| "modem_message"
---| "monitor_resize"
---| "monitor_touch"
---| "mouse_click"
---| "mouse_drag"
---| "mouse_scroll"
---| "mouse_up"
---| "double_click" (custom)
---| "paste"
---| "peripheral"
---| "peripheral_detach"
---| "rednet_message"
---| "redstone"
---| "speaker_audio_empty"
---| "task_complete"
---| "term_resize"
---| "terminate"
---| "timer"
---| "turtle_inventory"
---| "websocket_closed"
---| "websocket_failure"
---| "websocket_message"
---| "websocket_success"
---| "clock_start" (custom)

--#endregion

return types