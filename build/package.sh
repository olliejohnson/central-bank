#!/bin/bash

# Creates zips to attach to GitHub releases.
# These can be extracted onto a computer and will include all files CBIN would otherwise install.

tag=$(git describe --tags)
apps=(server)

for app in "${apps[@]}" do
    mkdir ${tag}_${app}
    cp -R $app cb-common graphics ccryptolib ecnet2 configure.lua initenv.lua startup.lua LICENSE ${tag}_${app}
    zip -r ${tag}_${app}.zip ${tag}_${app}
    rm -R ${tag}_${app}
done