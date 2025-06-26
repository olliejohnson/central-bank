import json
import os
import sys

# list files in a directory
def list_files(path):
    list = []

    for (root, dirs, files) in os.walk(path):
        for f in files:
            list.append((root[2:] + "/" + f).replace('\\', '/'))
    
    return list

# get size of all files in a directory
def dir_size(path):
    total = 0

    for (root, dirs, files) in os.walk(path):
        for f in files:
            total += os.path.getsize(root + "/" + f)
    
    return total

# get the version of an application at the provided path
def get_version(path, is_lib = False):
    ver = ""
    string = ".version = \""

    if not is_lib:
        string = "_VERSION = \""

    f = open(path, "r")

    for line in f:
        pos = line.find(string)
        if pos >= 0:
            ver = line[(pos + len(string)):(len(line) - 2)]
            break

    f.close()

    return ver

# generate installation manifest object
def make_manifest(size):
    manifest = {
        "versions" : {
            "installer" : get_version("./cbin.lua"),
            "bootloader" : get_version("./startup.lua"),
            "common" : get_version("./cb-common/util.lua", True),
            "graphics" : get_version("./graphics/core.lua", True),
            "server": get_version("./cb-server/startup.lua"),
        },
        "files" : {
            # common files
            "system" : [ "initenv.lua", "startup.lua", "configure.lua", "LICENSE" ],
            "common" : list_files("./scada-common"),
            "graphics" : list_files("./graphics"),
            "ccryptolib": list_files("./ccrytolib"),
            "ecnet2": list_files("./ecnet2"),
            # platform files
            "server": list_files("./cb-server")
        },
        "depends" : {
            "server" : [ "system", "common", "graphics", "ccryptolib", "ecnet2" ],
        },
        "sizes" : {
            # manifest file estimate
            "manifest" : size,
            # common files
            "system" : os.path.getsize("initenv.lua") + os.path.getsize("startup.lua") + os.path.getsize("configure.lua"),
            "common" : dir_size("./cb-common"),
            "graphics" : dir_size("./graphics"),
            "ccryptolib" : dir_size("./ccryptolib"),
            "ecnet2": dir_size("./ecnet2"),
            # platform files
            "server": dir_size("./cb-server")
        }
    }

    return manifest

# write initial manifest with placeholder size
f = open("install_manifest.json", "w")
json.dump(make_manifest("-----"), f)
f.close()

manifest_size = os.path.getsize("install_manifest.json")

final_manifest = make_manifest(manifest_size)

# calculate the file size then regenerate with embedded size
f = open("install_manifest.json", "w")
json.dump(final_manifest, f)
f.close()

if len(sys.argv) > 1 and sys.argv[1] == "shields":
    # write all the JSON files for shields.io
    for key, version in final_manifest["versions"].items():
        f = open("./deploy/" + key + ".json", "w")

        if version.find("alpha") >= 0:
            color = "yellow"
        elif version.find("beta") >= 0:
            color = "orange"
        else:
            color = "blue"
        
        json.dump({
            "schemaVersion": 1,
            "label": key,
            "message": "" + version,
            "color": color
        }, f)

        f.close()