#!/bin/sh
# Xcode ▸ Settings ▸ Behaviors ▸ Build ▸ Starts ▸ Run script → this file.
open -g "dynamictouchbar://progress?id=xcode-build&title=Building%20${XcodeProject:-project}"
