--
-- Protected Peripheral Manager
--

local log  = require("cb-common.log")
local util = require("cb-common.util")

---@class ppm
local ppm = {}

local ACCESS_FAULT        = nil                 ---@type nil
local UNDEFINED_FIELD     = "__PPM_UNDEF_FIELD__"
local VIRTUAL_DEVICE_TYPE = "ppm_vdev"

ppm.ACCESS_FAULT          = ACCESS_FAULT
ppm.UNDEFINED_FIELD       = UNDEFINED_FIELD
ppm.VIRTUAL_DEVICE_TYPE   = VIRTUAL_DEVICE_TYPE

----------------------------
-- PRIVATE DATA/FUNCTIONS --
----------------------------

local REPORT_FREQUENCY = 20 -- log every 20 faults per function

local ppm_sys = {
    mounts = {},    ---@type { [string]: ppm_entry }
    next_vid = 0,
    auto_cf = false,
    faulted = false,
    last_fault = "",
    terminate = false,
    mute = false
}

-- Wrap peripheral calls with lua protected call as we don't want a disconnect to crash a program.
-- Additionally provides peripheral-specific fault checks (auto-clear fault defaults to true).<br>
-- Note: assumes iface is a valid peripheral.
---@param iface string CC peripheral interface
local function peri_init(iface)
    local self = {
        faulted = false,
        last_fault = "",
        fault_counts = {},          ---@type { [string]: integer }
        auto_cf = true,
        type = VIRTUAL_DEVICE_TYPE, ---@type string
        device = {}                 ---@type { [string]: function }
    }

    if iface ~= "__virtual__" then
        self.type = peripheral.getType(iface)
        self.device = peripheral.wrap(iface)
    end

    -- create a protected version of a peripheral function call
    ---@nodiscard
    ---@param key string function name
    ---@param func function function
    ---@return function method protected version of the function
    local function protect_peri_function(key, func)
        return function (...)
            local return_table = table.pack(pcall(func, ...))

            local status = return_table[1]
            table.remove(return_table, 1)

            if status then
                -- auto fault clear
                if self.auto_cf then self.faulted = false end
                if ppm_sys.auto_cf then ppm_sys.faulted = false end

                self.fault_counts[key] = 0

                return table.unpack(return_table)
            else
                local result = return_table[1]

                -- function failed
                self.faulted = true
                self.last_fault = result

                ppm_sys.faulted = true
                ppm_sys.last_fault = result

                if not ppm_sys.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
                    local count_str = ""
                    if self.fault_counts[key] > 0 then
                        count_str = " [" .. self.fault_counts[key] .. " total faults]"
                    end

                    log.error(util.c("PPM: [@", iface, "] protected ", key, "() -> ", result, count_str))
                end

                self.fault_counts[key] = self.fault_counts[key] + 1

                if result == "Terminated" then ppm_sys.terminate = true end

                return ACCESS_FAULT, result
            end
        end
    end

    -- initialization process (re-map)
    for key, func in pairs(self.device) do
        self.fault_counts[key] = 0
        self.device[key] = protect_peri_function(key, func)
    end

    -- fault management & monitoring functions

    local function clear_fault() self.faulted = false end
    local function get_last_fault() return self.last_fault end
    local function is_faulted() return self.faulted end
    local function is_ok() return not self.faulted end

    -- check if a peripheral has any faulted functions<br>
    -- contrasted with is_faulted() and is_ok() as those only check if the last operation failed,
    -- unless auto fault clearing is disabled, at which point faults become sticky faults
    local function is_healthy()
        for _, v in pairs(self.fault_counts) do if v > 0 then return false end end
        return true
    end

    local function enable_afc() self.auto_cf = true end
    local function disable_afc() self.auto_cf = false end

    -- append PPM functions to device functions

    self.device.__p_clear_fault = clear_fault
    self.device.__p_last_fault  = get_last_fault
    self.device.__p_is_faulted  = is_faulted
    self.device.__p_is_ok       = is_ok
    self.device.__p_is_healthy  = is_healthy
    self.device.__p_enable_afc  = enable_afc
    self.device.__p_disable_afc = disable_afc

    -- add default index function to catch undefined indicies

    local mt = {
        __index = function (_, key)
            -- try to find the function in case it was added (multiblock formed)
            local funcs = peripheral.wrap(iface)
            if (type(funcs) == "table") and (type(funcs[key]) == "function") then
                -- add this function then return it
                self.fault_counts[key] = 0
                self.device[key] = protect_peri_function(key, funcs[key])

                log.info(util.c("PPM: [@", iface, "] initialized previously undefined field ", key, "()"))

                return self.device[key]
            end

            -- function still missing, return an undefined function handler
            -- note: code should avoid storing functions for multiblocks and instead try to index them again
            return (function ()
                -- this will continuously be counting calls here as faults
                if self.fault_counts[key] == nil then self.fault_counts[key] = 0 end

                -- function failed
                self.faulted = true
                self.last_fault = UNDEFINED_FIELD

                ppm_sys.faulted = true
                ppm_sys.last_fault = UNDEFINED_FIELD

                if not ppm_sys.mute and (self.fault_counts[key] % REPORT_FREQUENCY == 0) then
                    local count_str = ""
                    if self.fault_counts[key] > 0 then
                        count_str = " [" .. self.fault_counts[key] .. " total calls]"
                    end

                    log.error(util.c("PPM: [@", iface, "] caught undefined function ", key, "()", count_str))
                end

                self.fault_counts[key] = self.fault_counts[key] + 1

                return ACCESS_FAULT, UNDEFINED_FIELD
            end)
        end
    }

    setmetatable(self.device, mt)

    ---@class ppm_entry
    local entry = { type = self.type, dev = self.device }

    return entry
end

----------------------
-- PUBLIC FUNCTIONS --
----------------------

-- REPORTING --

-- silence error prints
function ppm.disable_reporting() ppm_sys.mute = true end

-- allow error prints
function ppm.enable_reporting() ppm_sys.mute = false end

-- FAULT MEMORY --

-- enable automatically clearing fault flag
function ppm.enable_afc() ppm_sys.auto_cf = true end

-- disable automatically clearing fault flag
function ppm.disable_afc() ppm_sys.auto_cf = false end

-- clear fault flag
function ppm.clear_fault() ppm_sys.faulted = false end

-- check fault flag
---@nodiscard
function ppm.is_faulted() return ppm_sys.faulted end

-- get the last fault message
---@nodiscard
function ppm.get_last_fault() return ppm_sys.last_fault end

-- TERMINATION --

-- if a caught error was a termination request
---@nodiscard
function ppm.should_terminate() return ppm_sys.terminate end

-- MOUNTING --

-- mount all available peripherals (clears mounts first)
function ppm.mount_all()
    local ifaces = peripheral.getNames()

    ppm_sys.mounts = {}

    for i = 1, #ifaces do
        ppm_sys.mounts[ifaces[i]] = peri_init(ifaces[i])

        log.info(util.c("PPM: found a ", ppm_sys.mounts[ifaces[i]].type, " (", ifaces[i], ")"))
    end

    if #ifaces == 0 then
        log.warning("PPM: mount_all() -> no devices found")
    end
end

-- mount a specified device
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, table|nil device
function ppm.mount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            ppm_sys.mounts[iface] = peri_init(iface)

            pm_type = ppm_sys.mounts[iface].type
            pm_dev = ppm_sys.mounts[iface].dev

            log.info(util.c("PPM: mount(", iface, ") -> found a ", pm_type))
            break
        end
    end

    return pm_type, pm_dev
end

-- unmount and remount a specified device
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, table|nil device
function ppm.remount(iface)
    local ifaces = peripheral.getNames()
    local pm_dev = nil
    local pm_type = nil

    for i = 1, #ifaces do
        if iface == ifaces[i] then
            log.info(util.c("PPM: remount(", iface, ") -> is a ", pm_type))
            ppm.unmount(ppm_sys.mounts[iface].dev)

            ppm_sys.mounts[iface] = peri_init(iface)

            pm_type = ppm_sys.mounts[iface].type
            pm_dev = ppm_sys.mounts[iface].dev

            log.info(util.c("PPM: remount(", iface, ") -> remounted a ", pm_type))
            break
        end
    end

    return pm_type, pm_dev
end

-- mount a virtual, placeholder device (specifically designed for RTU startup with missing devices)
---@nodiscard
---@return string type, table device
function ppm.mount_virtual()
    local iface = "ppm_vdev_" .. ppm_sys.next_vid

    ppm_sys.mounts[iface] = peri_init("__virtual__")
    ppm_sys.next_vid = ppm_sys.next_vid + 1

    log.info(util.c("PPM: mount_virtual() -> allocated new virtual device ", iface))

    return ppm_sys.mounts[iface].type, ppm_sys.mounts[iface].dev
end

-- manually unmount a peripheral from the PPM
---@param device table device table
function ppm.unmount(device)
    if device then
        for iface, data in pairs(ppm_sys.mounts) do
            if data.dev == device then
                log.warning(util.c("PPM: manually unmounted ", data.type, " mounted to ", iface))
                ppm_sys.mounts[iface] = nil
                break
            end
        end
    end
end

-- handle peripheral_detach event
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type, table|nil device
function ppm.handle_unmount(iface)
    local pm_dev = nil
    local pm_type = nil

    -- what got disconnected?
    local lost_dev = ppm_sys.mounts[iface]

    if lost_dev then
        pm_type = lost_dev.type
        pm_dev = lost_dev.dev

        log.warning(util.c("PPM: lost device ", pm_type, " mounted to ", iface))
    else
        log.error(util.c("PPM: lost device unknown to the PPM mounted to ", iface))
    end

    ppm_sys.mounts[iface] = nil

    return pm_type, pm_dev
end

-- log all mounts, to be used if `ppm.mount_all` is called before logging is ready
function ppm.log_mounts()
    for iface, mount in pairs(ppm_sys.mounts) do
        log.info(util.c("PPM: had found a ", mount.type, " (", iface, ")"))
    end

    if util.table_len(ppm_sys.mounts) == 0 then
        log.warning("PPM: no devices had been found")
    end
end

-- GENERAL ACCESSORS --

-- list all available peripherals
---@nodiscard
---@return string[] names
function ppm.list_avail() return peripheral.getNames() end

-- list mounted peripherals
---@nodiscard
---@return { [string]: ppm_entry } mounts
function ppm.list_mounts()
    local list = {}
    for k, v in pairs(ppm_sys.mounts) do list[k] = v end
    return list
end

-- get a mounted peripheral side/interface by device table
---@nodiscard
---@param device table device table
---@return string|nil iface CC peripheral interface
function ppm.get_iface(device)
    if device then
        for iface, data in pairs(ppm_sys.mounts) do
            if data.dev == device then return iface end
        end
    end

    return nil
end

-- get a mounted peripheral by side/interface
---@nodiscard
---@param iface string CC peripheral interface
---@return { [string]: function }|nil device function table
function ppm.get_periph(iface)
    if ppm_sys.mounts[iface] then
        return ppm_sys.mounts[iface].dev
    else return nil end
end

-- get a mounted peripheral type by side/interface
---@nodiscard
---@param iface string CC peripheral interface
---@return string|nil type
function ppm.get_type(iface)
    if ppm_sys.mounts[iface] then
        return ppm_sys.mounts[iface].type
    else return nil end
end

-- get all mounted peripherals by type
---@nodiscard
---@param name string type name
---@return table devices device function tables
function ppm.get_all_devices(name)
    local devices = {}

    for _, data in pairs(ppm_sys.mounts) do
        if data.type == name then
            table.insert(devices, data.dev)
        end
    end

    return devices
end

-- get a mounted peripheral by type (if multiple, returns the first)
---@nodiscard
---@param name string type name
---@return table|nil device function table
function ppm.get_device(name)
    local device = nil

    for _, data in pairs(ppm_sys.mounts) do
        if data.type == name then
            device = data.dev
            break
        end
    end

    return device
end

-- SPECIFIC DEVICE ACCESSORS --

-- get the wireless modem (if multiple, returns the first)<br>
-- if this is in a CraftOS emulated environment, wired modems will be used instead
---@nodiscard
---@return Modem|nil modem function table
function ppm.get_wireless_modem()
    local w_modem = nil
    local emulated_env = periphemu ~= nil

    for _, device in pairs(ppm_sys.mounts) do
        if device.type == "modem" and (emulated_env or device.dev.isWireless()) then
            w_modem = device.dev
            break
        end
    end

    return w_modem
end

-- list all connected monitors
---@nodiscard
---@return { [string]: ppm_entry } monitors
function ppm.get_monitor_list()
    local list = {}

    for iface, device in pairs(ppm_sys.mounts) do
        if device.type == "monitor" then list[iface] = device end
    end

    return list
end

-- HELPER FUNCTIONS

-- get the block size of a monitor given its width and height <b>at a text scale of 0.5</b>
---@nodiscard
---@param width integer character width
---@param height integer character height
---@return integer block_width, integer block_height
function ppm.monitor_block_size(width, height)
    return math.floor((width - 15) / 21) + 1, math.floor((height - 10) / 14) + 1
end

return ppm