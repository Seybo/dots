#!/bin/bash

# Strip only zsh prompt formatting codes, keep ANSI colors
starship prompt 2>/dev/null | sed -E 's/%\{[^}]*\}//g' | tr -d '\n' | sed 's/[[:space:]]*$//'
