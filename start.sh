#!/bin/bash
# The container's entry point: runs the given script once, then opens a shell in /repro to look around. When the
# container is started again (docker start -ai), runs/ already exists and it goes straight to the shell.
if [ ! -d /repro/runs ]; then
    bash "/repro/$1"
fi
exec bash
