---@type ChatBox
local chatBox = peripheral.find("chat_box")

chatBox.sendToastToPlayer("Test", "supa", "jacoberrol")

chatBox.sendFormattedMessageToPlayer({ text = "Hello", bold = true, hover_event = { action = "show_text", value = { text = "Hover", color = "red", bold = true } } }, "jacoberrol", "", "")

---@class server
local server = {}

-- cb-server version
server.version = "1.0.0"

return server