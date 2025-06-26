print("CONFIGURE> SCANNING FOR CONFIGURATION...")

for _, app in ipairs({ "server" }) do
    if fs.exists(app .. "./configure.lua") then
        local _, _, launch = require(app .. ".configure").configure()
        if launch then shell.execute("/startup") end
        return
    end
end

print("CONFIGURE> NO CONFIGURATOR FOUND")
print("CONFIGURE> EXIT")