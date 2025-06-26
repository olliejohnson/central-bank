local BOOTLOADER_VERSION = "1.0"

print("Central Bank BOOTLOADER V"..BOOTLOADER_VERSION)
print("BOOT> SCANNING FOR APPLICATIONS...")

local exit_code

if fs.exists("server/startup.lua") then
    print("BOOT> EXEC SERVER STARTUP")
    exit_code = shell.execute("server/startup")
else
    print("BOOT> NO Central Bank STARTUP FOUND")
    print("BOOT> EXIT")
    return false
end

if not exit_code then print("BOOT> APPLICATION_CRASHED") end

return exit_code