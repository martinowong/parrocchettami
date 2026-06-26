on run argv
    set volumeName to item 1 of argv
    delay 2

    tell application "Finder"
        set targetDisk to disk (volumeName as string)
        open targetDisk
        delay 1

        set targetWindow to container window of targetDisk
        set current view of targetWindow to icon view
        set toolbar visible of targetWindow to false
        set statusbar visible of targetWindow to false
        set pathbar visible of targetWindow to false
        set bounds of targetWindow to {120, 120, 780, 612}

        set viewOptions to icon view options of targetWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff" of targetDisk

        set position of item "Parrocchettami.app" of targetDisk to {160, 195}
        set position of item "Applications" of targetDisk to {500, 195}
        set position of item "Installation Guide.txt" of targetDisk to {330, 365}
        update targetDisk without registering applications
        delay 2
        close targetWindow
    end tell
end run
