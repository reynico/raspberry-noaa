#!/bin/bash

### Run as a normal user
if [ $EUID -eq 0 ]; then
    echo "This script shouldn't be run as root."
    exit 1
fi

## import common lib
. "$HOME/.noaa.conf"
. "$NOAA_HOME/common.sh"

if [ -z "$1" ]; then
    log "Usage: $0 <frequency>. Example: $0 90.3" "ERROR"
    exit 1
fi

command_exists() {
    if ! command -v "$1" &> /dev/null; then
        log "Required command not found: $1" "ERROR"
        exit 1
    fi
}

command_exists "sox"
command_exists "socat"

IP=$(ip route | grep "link src" | awk {'print $NF'})

if pgrep "rtl_fm" > /dev/null
then
    log "There is an existing rtl_fm instance running, I quit" "ERROR"
    exit 1
fi

echo "$(tput setaf 2)
    The server is in testing mode tuned to $1 Mhz!
    Open a terminal in your computer and paste:
    ncat $IP 8073 | play -t mp3 -
    $(tput sgr0)
"

echo "rtl_fm ${BIAS_TEE} -f "$1M" -s 256k $GAIN -p $PPM_ERROR -E deemp -F 9 -"
rtl_fm ${BIAS_TEE} -f "$1M" -s 256k $GAIN -p $PPM_ERROR -E deemp -F 9 - \
        | sox -traw -r256k -es -b16 -c1 -V1 - -tmp3 - \
        | socat -u - TCP-LISTEN:8073 1>/dev/null
