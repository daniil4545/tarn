#!/bin/zsh
# Runs as the only command of a bench surface: cat <file> to the terminal, write the wall time in seconds to <out>.
zmodload zsh/datetime
start=$EPOCHREALTIME
cat "$1"
end=$EPOCHREALTIME
print $(( end - start )) > "$2.tmp" && mv "$2.tmp" "$2"
