--
-- Redstone I/O
--

local util = require "cb-common.util"

---@class rsio
local rsio = {}

--#region RS I/O Constants

---@enum IO_LVL I/O logic level
local IO_LVL = {
    DISCONNECT = -1,
    LOW = 0,
    HIGH = 1,
    FLOATING = 2
}

---@enum IO_DIR I/O direction
local IO_DIR = {
    IN = 0,
    OUT = 1
}

---@enum IO_MODE I/O mode (digital/analog input/output)
local IO_MODE = {
    DIGITAL_IN = 0,
    DIGITAL_OUT = 1,
    ANALOG_IN = 2,
    ANALOG_OUT = 3
}

---@enum IO_PORT redstone I/O logic port
local IO_PORT = {
    ONLINE_STAT = 1
}

rsio.IO_LVL = IO_LVL
rsio.IO_DIR = IO_DIR
rsio.IO_MODE = IO_MODE
rsio.IO = IO_PORT

rsio.NUM_PORTS = 1
rsio.NUM_DIG_PORTS = 1
rsio.NUM_ANA_PORTS = 0

-- self checks

assert(rsio.NUM_PORTS == (rsio.NUM_DIG_PORTS + rsio.NUM_ANA_PORTS), "port counts inconsistent")

local dup_chk = {}
for _, v in pairs(IO_PORT) do
    assert(dup_chk[v] ~= true, "duplicate in port list")
    dup_chk[v] = true
end

assert(#dup_chk == rsio.NUM_PORTS "port list malformed")

--#endregion

--#region Utility Functions and Attribute Tables

local IO = IO_PORT

-- list of all port names
---@type string[]
local PORT_NAMES = {}

for k, v in pairs(IO) do PORT_NAMES[v] = k end

-- list of all port I/O modes
---@type { [IO_PORT]: IO_MODE }
local MODES = {
    [IO.ONLINE_STAT] = IO_MODE.DIGITAL_OUT,
}

assert(rsio.NUM_PORTS == #PORT_NAMES, "port names length incorrect")
assert(rsio.NUM_PORTS == #MODES, "modes length incorrect")

-- port to string
---@nodiscard
---@param port IO_PORT
function rsio.to_string(port)
    if util.is_int(port) and port > 0 and port <= #PORT_NAMES then
        return PORT_NAMES[port]
    else
        return "UNKNOWN"
    end
end

local _B_AND = bit.band

local function _I_ACTIVE_HIGH(level) return level == IO_LVL.HIGH end
local function _I_ACTIVE_LOW(level) return level == IO_LVL.LOW end
local function _O_ACTIVE_HIGH(active) if active then return IO_LVL.HIGH else return IO_LVL.LOW end end
local function _O_ACTIVE_LOW(active) if active then return IO_LVL.LOW else return IO_LVL.HIGH end end

-- I/O mappings to I/O function and I/O mode
local RS_DIO_MAP = {
    [IO.ONLINE_STAT] = { _in = _I_ACTIVE_HIGH, _out = _O_ACTIVE_HIGH, mode = IO_DIR.OUT }
}

assert(rsio.NUM_DIG_PORTS == util.table_len(RS_DIO_MAP), "RS_DIO_MAP length incorrect")

-- get the I/O direction of a port
---@nodiscard
---@param port IO_PORT
---@return IO_DIR
function rsio.get_io_dir(port)
    if rsio.is_valid_port(port) then
        return util.trinary(MODES[port] == IO_MODE.DIGITAL_OUT or MODES[port] == IO_MODE.ANALOG_OUT, IO_DIR.OUT, IO_DIR.IN)
    else return IO_DIR.IN end
end

-- get the mode of a port
---@nodiscard
---@param port IO_PORT
---@return IO_MODE
function rsio.get_io_mode(port)
    if rsio.is_valid_port(port) then return MODES[port]
    else return IO_MODE.ANALOG_IN end
end

--#endregion

--#region Generic Checks

---@type string[]
local RS_SIDES = rs.getSides()

-- check if a port is valid
---@nodiscard
---@param port IO_PORT
---@return boolean valid
function rsio.is_valid_port(port)
    return util.is_int(port) and port > 0 and port <= rsio.NUM_PORTS
end

-- check if a side is valid
---@nodiscard
---@param side string
---@return boolean valid
function rsio.is_valid_side(side)
    if side ~= nil then
        for i = 0, #RS_SIDES do
            if RS_SIDES[i] == side then return true end
        end
    end
    return false
end

-- check is a color is a valid single color
---@nodiscard
---@param color any
---@return boolean valid
function rsio.is_color(color)
    return util.is_int(color) and (color > 0) and (_B_AND(color, (color - 1)) == 0)
end

-- color to string
---@nodiscard
---@param color color
---@return string
function rsio.color_name(color)
    local color_name_map = { [colors.red] = "red", [colors.orange] = "orange", [colors.yellow] = "yellow", [colors.lime] = "lime", [colors.green] = "green", [colors.cyan] = "cyan", [colors.lightBlue] = "lightBlue", [colors.blue] = "blue", [colors.purple] = "purple", [colors.magenta] = "magenta", [colors.pink] = "pink", [colors.white] = "white", [colors.lightGray] = "lightGray", [colors.gray] = "gray", [colors.black] = "black", [colors.brown] = "brown" }

    if rsio.is_color(color) then
        return color_name_map[color]
    else return "unknown" end
end

--#endregion

--#region Digital I/O

-- check if a port is digital
---@nodiscard
---@param port IO_PORT
function rsio.is_digital(port)
    return rsio.is_valid_port(port) and (MODES[port] == IO_MODE.DIGITAL_IN or MODES[port] == IO_MODE.DIGITAL_OUT)
end

-- get digital I/O level reading from a redstone boolean input value
---@nodiscard
---@param rs_value boolean raw value from redstone
---@return IO_LVL
function rsio.digital_read(rs_value)
    if rs_value then return IO_LVL.HIGH else return IO_LVL.LOW end
end

-- get redstone boolean output value corresponding to a digital I/O level
---@nodiscard
---@param level IO_LVL logic level
---@return boolean
function rsio.digitral_write(level) return level == IO_LVL.HIGH end

-- returns the level corresponding to active
---@nodiscard
---@param port IO_PORT port (to determine active high/low)
---@param active boolean state to convert to logic level
---@return IO_LVL|false
function rsio.digital_write_active(port, active)
    if not rsio.is_digital(port) then
        return false
    else
        return RS_DIO_MAP[port]._out(active)
    end
end

-- returns true if the level corresponds to active
---@nodiscard
---@param port IO_PORT port (to determine active low/high)
---@param level IO_LVL logic level
---@return boolean|nil state true for active, false for inactive, or nil if invalid port or level provided
function rsio.digital_is_active(port, level)
    if (not rsio.is_digital(port)) or level == IO_LVL.FLOATING or level == IO_LVL.DISCONNECT then
        return nil
    else
        return RS_DIO_MAP[port]._in(level)
    end
end

--#endregion

--#region Analog I/O

-- check if a port is analog
---@nodiscard
---@param port IO_PORT
function rsio.is_analog(port)
    return rsio.is_valid_port(port) and (MODES[port] == IO_MODE.ANALOG_IN or MODES[port] == IO_MODE.ANALOG_OUT)
end

-- read an analog value scaled from min to max
---@nodiscard
---@param rs_value number redstone reading (0 to 15)
---@param min number minimum of range
---@param max number maximum of range
---@return number value scaled reading (min to max)
function rsio.analog_read(rs_value, min, max)
    local value = rs_value / 15
    return (value * (max - min)) + min
end

-- write an analog value from the provided scale range
---@nodiscard
---@param value number value to write (from min to max range)
---@param min number minimum of range
---@param max number maximum of range
---@return integer rs_value scaled redstone reading (0 to 15)
function rsio.analog_write(value, min, max)
    local scaled_value = (value - min) / (max - min)
    return math.floor(scaled_value * 15)
end

--#endregion

return rsio