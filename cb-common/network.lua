--
-- Network Communications
--

local comms = require "cb-common.comms"
local log = require "cb-common.log"
local util = require "cb-common.util"

local md5    = require("lockbox.digest.md5")
local sha1   = require("lockbox.digest.sha1")
local pbkdf2 = require("lockbox.kdf.pbkdf2")
local hmac   = require("lockbox.mac.hmac")
local stream = require("lockbox.util.stream")
local array  = require("lockbox.util.array")

---@class net_interface
local network = {}

-- cryptography engine
local c_eng = {
    key = nil,
    hmac = nil
}

-- initialize message authentication system
---@param passkey string passkey
---@return integer init_time milliseconds init took
function network.init_mac(passkey)
    local start = util.time_ms()

    local key_deriv = pbkdf2()

    -- setup PBKDF2
    key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha1))
    key_deriv.setBlockLen(20)
    key_deriv.setDKeyLen(20)
    key_deriv.setIterations(256)
    key_deriv.setSalt("pepper")
    key_deriv.setPassword(passkey)
    key_deriv.finish()

    c_eng.key = array.fromHex(key_deriv.asHex())

    -- initialize HMAC
    c_eng.hmac = hmac()
    c_eng.hmac.setBlockSize(64)
    c_eng.hmac.setDigest(md5)
    c_eng.hmac.setKey(c_eng.key)

    local init_time = util.time_ms() - start
    log.info("network.init_mac completed in" .. init_time .. "ms")

    return init_time
end

-- de-initialize message authentication system
function network.deinit_mac()
    c_eng.key, c_eng.hmac = nil, nil
end

-- generate HMAC of message
---@nodiscard
---@param message string initial value concatenated with ciphertext
local function compute_hmac(message)
    c_eng.hmac.init()
    c_eng.hmac.update(stream.fromString(message))
    c_eng.hmac.finish()

    local hash = c_eng.hmac.asHex()

    return hash
end

-- NIC: Network Interface Controller<br>
-- utilizes HMAC-MD5 for message authentication, if enabled
---@param modem Modem modem to use
function network.nic(modem)
    local self = {
        connected = true, -- used to avoid costly MAC calculations if modem isn't even present
        channels = {}
    }

    ---@class nic:Modem
    local public = {}

    -- check if this NIC has a connected modem
    ---@nodiscard
    function public.is_connected() return self.connected end

    -- connect to a modem peripheral
    ---@param reconnected_modem Modem
    function public.connect(reconnected_modem)
        modem = reconnected_modem
        self.connected = true

        -- open previously opened channels
        for _, channel in ipairs(self.channels) do
            modem.open(channel)
        end

        -- link all public functions except for transmit, open, and close
        for key, func in pairs(modem) do
            if key ~= "transmit" and key ~= "open" and key ~= "close" and key ~= "closeAll" then public[key] = func end
        end
    end

    -- flag this NIC as no longer having a connected modem (usually do to peripheral disconnect)
    function public.disconnect() self.connected = false end

    -- check if a peripheral is this modem
    ---@nodiscard
    ---@param device table
    function public.is_modem(device) return device == modem end

    -- wrap modem functions, then create custom function
    public.connect(modem)

    -- open a channel on the modem<br>
    -- if disconnected *after* opening, previously opened channels will be re-opened on reconnection
    ---@param channel integer
    function public.open(channel)
        modem.open(channel)

        local already_open = false
        for i = 1, #self.channels do
            if self.channels[i] == channel then
                already_open = true
                break
            end
        end

        if not already_open then
            table.insert(self.channels, channel)
        end
    end

    -- close a channel on the modem
    ---@param channel integer
    function public.close(channel)
        modem.close(channel)

        for i = 1, #self.channels do
            if self.channels[i] == channel then
                table.remove(self.channels, i)
                return
            end
        end
    end

    -- close all channels on the modem
    function public.closeAll()
        modem.closeAll()
        self.channels = {}
    end

    -- send a packet, with message authentication if configured
    ---@param dest_channel integer destination channel
    ---@param local_channel integer local channel
    ---@param packet packet packet
    function public.transmit(dest_channel, local_channel, packet)
        if self.connected then
            local tx_packet = packet ---@type authd_packet|packet

            if c_eng.hmac ~= nil then
                tx_packet = comms.authd_packet()

                ---@cast tx_packet authd_packet
                tx_packet.make(packet, compute_hmac)
            end

            modem.transmit(dest_channel, local_channel, tx_packet.raw_sendable())
        end
    end

    -- parse in a modem message as a network packet
    ---@nodiscard
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any packet sent with or without message authentication
    ---@param distance integer transmission distance
    ---@return packet|nil packet recevied packet if valid and passed authentication check
    function public.receive(side, sender, reply_to, message, distance)
        local packet = nil

        if self.connected then
            local s_packet = comms.packet()

            if c_eng.hmac ~= nil then
                -- parse packet as an authenticated packet
                local a_packet = comms.authd_packet()
                a_packet.receive(side, sender, reply_to, message, distance)

                if a_packet.is_valid() then
                    s_packet.receive(side, sender, reply_to, message, distance)

                    if s_packet.is_valid() then
                        local computed_hmac = compute_hmac(textutils.serialise(s_packet.raw_header(), { allow_repetitions = true, compact = true }))

                        if a_packet.mac() == computed_hmac then
                            s_packet.stamp_authentication()
                        else
                            --
                        end
                    end
                end
            else
                -- parse packet as a generic packet
                s_packet.receive(side, sender, reply_to, message, distance)
            end

            if s_packet.is_valid() then packet = s_packet end
        end

        return packet
    end

    return public
end

return network