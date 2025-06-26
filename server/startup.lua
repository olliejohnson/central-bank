---@type ChatBox
local chatBox = peripheral.find("chat_box")

chatBox.sendToastToPlayer("Test", "supa", "jacoberrol")

---@class server
local server = {}

-- cb-server version
server.version = "1.0.0"

return server