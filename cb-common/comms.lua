--
-- Communications
--

local log = require "cb-common.log"

local insert = table.insert

---@type integer computer ID
---@diagnostic disable-next-line: undefined-field
local COMPUTER_ID = os.getComputerID()

---@type number|nil maximum acceptable transmission distance
local max_distance = nil

---@class comms
local comms = {}

-- protocol/data version (protocol/data independent changes tracked by util.lua version)
comms.version = "0.0.1"
comms.api_version = "0.0.1"

---@enum PROTOCOL
local PROTOCOL = {
    C_PROTO = 0
}

---@enum CLI_TYPES
local CLI_TYPES = {
    STATUS = 0, -- system status
    KEEP_ALIVE = 1,
    ESTABLISH = 2,
    CLOSE = 3
}

---@enum ESTABLISH_ACK
local ESTABLISH_ACK = {
    ALLOw = 0, -- link approved
    DENY = 1, -- link denied
    COLLISION = 2, -- link denied due to existing active link
    BAD_VERSION = 3, -- link denied due to comms version mismatch
    BAD_API_VERSION = 4 -- link denied due to api version mismatch
}

---@enum DEVICE_TYPE device types for established messages
local DEVICE_TYPE = { SVR = 0, CLI = 1 }

comms.PROTOCOL = PROTOCOL
comms.CLI_TYPES = CLI_TYPES

comms.ESTABLISH_ACK = ESTABLISH_ACK
comms.DEVICE_TYPE = DEVICE_TYPE

-- destination broacast address (to all devices)
comms.BROADCAST = -1

-- configure the maximum allowable message receive distance<br>
-- packets received with distances greater than this will be silently discarded
---@param distance integer max modmem message distance (0 disables the limit)
function comms.set_trusted_range(distance)
    if distance == 0 then max_distance = nil else max_distance = distance end
end

-- generic packet
---@nodiscard
function comms.packet()
    local self = {
        modem_msg_in = nil, ---@type modem_message|nil
        valid = false,
        authenticated = false,
        raw = {},
        src_addr = comms.BROADCAST,
        dest_addr = comms.BROADCAST,
        seq_num = -1,
        protocol = PROTOCOL.C_PROTO,
        length = 0,
        payload = {}
    }

    ---@class packet
    local public = {}

    -- make a packet
    ---@param dest_addr integer destination computer address (ID)
    ---@param seq_num integer sequence number
    ---@param protocol PROTOCOL
    ---@param payload table
    function public.make(dest_addr, seq_num, protocol, payload)
        self.valid = true
        self.src_addr = COMPUTER_ID
        self.dest_addr = dest_addr
        self.seq_num = seq_num
        self.protocol = protocol
        self.length = #payload
        self.payload = payload
        self.raw = { self.src_addr, self.dest_addr, self.seq_num, self.protocol, self.payload }
    end

    -- parse in a modem message as a packet
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid message received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_message
        self.modem_msg_in = {
            iface = side,
            s_channel = sender,
            r_channel = reply_to,
            msg = message,
            dist = distance
        }

        self.valid = false
        self.raw = self.modem_msg_in

        if (type(max_distance) == "number") and (type(distance) == "number") and (distance > max_distance) then
            -- outside of maximum allowable tranmission distance
            -- log.debug("comms.packet.receive(): discarding packet with distance " .. distance .. " (outside trusted range)")
        else
            if type(self.raw) == "table" then
                if #self.raw == 5 then
                    self.src_addr = self.raw[1]
                    self.dest_addr = self.raw[2]
                    self.seq_num = self.raw[3]
                    self.protocol = self.raw[4]

                    -- element 5 must be a table
                    if type(self.raw[5]) == "table" then
                        self.length = #self.raw[5]
                        self.payload = self.raw[5]
                    end
                else
                    self.src_addr = nil
                    self.dest_addr = nil
                    self.seq_num = nil
                    self.protocol = nil
                    self.length = 0
                    self.payload = {}
                end

                -- check if the packet is destined for this device
                local is_destination = (self.dest_addr == comms.BROADCAST) or (self.dest_addr == COMPUTER_ID)

                self.valid = is_destination and type(self.src_addr) == "number" and type(self.dest_addr) == "number" and
                    type(self.seq_num) == "number" and type(self.protocol) == "number" and type(self.payload) == "table"
            end
        end

        return self.valid
    end

    -- report this that packet has been authenticated (was received with a valid HMAC)
    function public.stamp_authenticated() self.authenticated = true end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_msg_in end
    ---@nodiscard
    function public.raw_header() return { self.src_addr, self.dest_addr, self.seq_num, self.protocol } end
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    ---@nodiscard
    function public.local_channel() return self.modem_msg_in.s_channel end
    ---@nodiscard
    function public.remote_channel() return self.modem_msg_in.r_channel end

    ---@nodiscard
    function public.is_valid() return self.valid end
    ---@nodiscard
    function public.is_authenticated() return self.authenticated end

    ---@nodiscard
    function public.src_addr() return self.src_addr end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr end
    ---@nodiscard
    function public.seq_num() return self.seq_num end
    ---@nodiscard
    function public.protocol() return self.protocol end
    ---@nodiscard
    function public.length() return self.length end
    ---@nodiscard
    function public.data() return self.payload end

    return public
end

-- authenticated packet
---@nodiscard
function comms.authd_packet()
    local self = {
        modem_msg_in = nil, ---@type modem_message|nil
        valid = false,
        raw = {},
        src_addr = comms.BROADCAST,
        dest_addr = comms.BROADCAST,
        mac = "",
        payload = {}
    }

    ---@class authd_packet
    local public = {}

    -- make an authenticated packet
    ---@param s_packet packet packet to authenticate
    ---@param mac function message authentication hash function
    function public.make(s_packet, mac)
        self.valid = true
        self.src_addr = s_packet.src_addr()
        self.dest_addr = s_packet.dest_addr()
        self.mac = mac(textutils.serialize(s_packet.raw_header(), { allow_repetitions = true, compact = true }))
        self.raw = { self.src_addr, self.dest_addr, self.mac, s_packet.raw_sendable() }
    end

    -- parse in a modem message as an authenticated packet
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any message body
    ---@param distance integer transmission distance
    ---@return boolean valid valid message received
    function public.receive(side, sender, reply_to, message, distance)
        ---@class modem_message
        self.modem_msg_in = {
            iface = side,
            s_channel = sender,
            r_channel = reply_to,
            msg = message,
            dist = distance
        }

        self.valid = false
        self.raw = self.modem_msg_in.msg

        if (type(max_distance) == "number") and ((type(distance) ~= "number") or (distance > max_distance)) then
            -- outside of maximum allowable transmission distance
            -- log.debug("comms.authd_packet.receive(): discarding packet with distance " .. distance .. " (outside trusted range)")
        else
            if type(self.raw) == "table" then
                if #self.raw == 4 then
                    self.src_addr = self.raw[1]
                    self.dest_addr = self.raw[2]
                    self.mac = self.raw[3]
                    self.payload = self.raw[4]
                else
                    self.src_addr = nil
                    self.dest_addr = nil
                    self.mac = ""
                    self.payload = {}
                end

                -- check if this packet is destined for this device
                local is_destination = (self.dest_addr == comms.BROADCAST) or (self.dest_addr == COMPUTER_ID)

                self.valid = is_destination and type(self.src_addr) == "number" and type(self.dest_addr) == "number" and
                                type(self.mac) == "string" and type(self.payload) == "table"
            end
        end

        return self.valid
    end

    -- public accessors --

    ---@nodiscard
    function public.modem_event() return self.modem_msg_in end
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    ---@nodiscard
    function public.local_channel() return self.modem_msg_in.s_channel end
    ---@nodiscard
    function public.remote_channel() return self.modem_msg_in.r_channel end

    ---@nodiscard
    function public.is_valid() return self.valid end

    ---@nodiscard
    function public.src_addr() return self.src_addr end
    ---@nodiscard
    function public.dest_addr() return self.dest_addr end
    ---@nodiscard
    function public.mac() return self.mac end
    ---@nodiscard
    function public.data() return self.payload end

    return public
end

-- client packet
---@nodiscard
function comms.cli_packet()
    local self = {
        frame = nil,
        raw = {},
        id = 0,
        type = 0, ---@type CLI_TYPES
        length = 0,
        data = {}
    }

    ---@class cli_packet
    local public = {}

    -- make an client packet
    ---@param id integer
    ---@param packet_type CLI_TYPES
    ---@param data table
    function public.make(id, packet_type, data)
        if type(data) == "table" then
            -- packet accessor properties
            self.id = id
            self.type = packet_type
            self.length = #data
            self.data = data

            -- populate raw array
            self.raw = { self.id, self.type }
            for i = 1, #data do insert(self.raw, data[i]) end
        else
            log.error("comms.cli_packet.make(): data not a table")
        end
    end

    -- decode an client packet from a frame
    ---@param frame packet
    ---@return boolean success
    function public.decode(frame)
        if frame then
            self.frame = frame

            if frame.protocol() == PROTOCOL.C_PROTO then
                local ok = frame.length() >= 2

                if ok then
                    local data = frame.data()
                    public.make(data[1], data[2], { table.unpack(data, 3, #data) })
                end

                ok = ok and type(self.id) == "number"

                return ok
            else
                log.debug("attempted client parse of incorrect protocol " .. frame.protocol(), true)
                return false
            end
        else
            log.debug("nil frame encountered", true)
            return false
        end
    end

    -- get raw to send
    ---@nodiscard
    function public.raw_sendable() return self.raw end

    -- get this packet as a frame with an immutable relation to this object
    ---@nodiscard
    function public.get()
        ---@class cli_frame
        local frame = {
            frame = self.frame,
            id = self.id,
            type = self.type,
            length = self.length,
            data = self.data
        }

        return frame
    end

    return public
end

return comms