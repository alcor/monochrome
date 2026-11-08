#!/bin/sh
# Chrome runs this as the extension's native messaging host (a host manifest can name a program but
# not its arguments); it's the app's binary in its host role.
exec "$(dirname "$0")/../MacOS/Monochrome" --host
