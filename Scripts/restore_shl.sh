#!/usr/bin/env bash
#|---/ /+---------------------------+---/ /|#
#|--/ /-| Script to configure shell |--/ /-|#
#|-/ /--| Prasanth Rangan           |-/ /--|#
#|/ /---+---------------------------+/ /---|#

scrDir=$(dirname "$(realpath "$0")")
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

# shellcheck disable=SC2154
if chk_list "myShell" "${shlList[@]}"; then
    print_log -sec "SHELL" -stat "detected" "${myShell}"
else
    print_log -sec "SHELL" -err "error" "no shell found..."
    exit 1
fi

# set shell
if [[ "$(grep "/${USER}:" /etc/passwd | awk -F '/' '{print $NF}')" != "${myShell}" ]]; then
    print_log -sec "SHELL" -stat "change" "shell to ${myShell}..."
    chsh -s "$(which "${myShell}")"
else
    print_log -sec "SHELL" -stat "exist" "${myShell} is already set as shell..."
fi
