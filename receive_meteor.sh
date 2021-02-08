#!/bin/bash

### Run as a normal user
if [ $EUID -eq 0 ]; then
    echo "This script shouldn't be run as root."
    exit 1
fi

## import common lib
. "$HOME/.noaa.conf"
. "$HOME/.tweepy.conf"
. "$NOAA_HOME/common.sh"

log "starting $0" DEBUG

SYSTEM_MEMORY=$(free -m | awk '/^Mem:/{print $2}')
if [ "$SYSTEM_MEMORY" -lt 2000 ]; then
    log "The system doesn't have enough space to store a Meteor pass on RAM" "INFO"
	RAMFS_AUDIO="${METEOR_OUTPUT}"
fi

if [ "$FLIP_METEOR_IMG" == "true" ]; then
    log "I'll flip this image pass because FLIP_METEOR_IMG is set to true" "INFO"
    FLIP="-rotate 180"
else
    FLIP=""
fi

## pass start timestamp and sun elevation
PASS_START=$(expr "$5" + 90)
SUN_ELEV=$(python3 "$NOAA_HOME"/sun.py "$PASS_START")

if pgrep "rtl_fm" > /dev/null
then
    log "There is an already running rtl_fm instance but I dont care for now, I prefer this pass" "INFO"
    pkill -9 -f rtl_fm
fi

# $1 = Satellite Name
# $2 = Frequency
# $3 = FileName base
# $4 = TLE File
# $5 = EPOC start time
# $6 = Time to capture
# $7 = Satellite max elevation

pre_rate=288k

log "Starting rtl_fm record for $1 at $2 to $3 at epoch $5" "INFO"
log "timeout \"${6}\" /usr/local/bin/rtl_fm ${BIAS_TEE} -p $PPM_ERROR -M raw -f ${2}M -F0 -s $pre_rate $GAIN | sox -t raw -r $pre_rate -c 2 -b 16 -e s - -t wav \"${RAMFS_AUDIO}/audio/${3}.wav\"" DEBUG
timeout "${6}" /usr/local/bin/rtl_fm ${BIAS_TEE} -p $PPM_ERROR -M raw -f ${2}M -F0 -s $pre_rate $GAIN | sox -t raw -r $pre_rate -c 2 -b 16 -e s - -t wav "${RAMFS_AUDIO}/audio/${3}.wav" #rate 96k

[[ $1 == "METEOR-M22" ]] && demod_extra="-m opsk"
log "Demodulation in progress (QPSK) $demod_extra" "INFO"
meteor_demod $demod_extra -B -o "${METEOR_OUTPUT}/${3}.qpsk" "${RAMFS_AUDIO}/audio/${3}.wav" 2>> $NOAA_LOG

if [ "$DELETE_AUDIO" = true ]; then
    log "Deleting audio files" "INFO"
    rm "${RAMFS_AUDIO}/audio/${3}.wav"
else
    log "Moving audio files out to the SD card" "INFO"
    mv "${RAMFS_AUDIO}/audio/${3}.wav" "${NOAA_OUTPUT}/audio/${3}.wav"
    rm "${METEOR_OUTPUT}/audio/${3}.wav"
    rm "${RAMFS_AUDIO}/audio/${3}.wav"
fi

log "Decoding in progress (QPSK to BMP)" INFO
[[ $1 == "METEOR-M22" ]] && medet_extra="-diff"
medet $medet_extra "${METEOR_OUTPUT}/${3}.qpsk" "${METEOR_OUTPUT}/${3}" -cd

rm "${METEOR_OUTPUT}/${3}.qpsk"

if [ -f "${METEOR_OUTPUT}/${3}.dec" ]; then
    log "Sun elevation: ${SUN_ELEV}" DEBUG
    if [ "${SUN_ELEV}" -lt "${SUN_MIN_ELEV}" ]; then
        log "I got a successful ${3}.dec file. Decoding APID 68" "INFO"
        medet "${METEOR_OUTPUT}/${3}.dec" "${NOAA_OUTPUT}/images/${3}-122" -r 68 -g 68 -b 68 -d
        /usr/bin/convert $FLIP -negate "${NOAA_OUTPUT}/images/${3}-122.bmp" "${NOAA_OUTPUT}/images/${3}-122.bmp"
    else
        log "I got a successful ${3}.dec file. Creating false color image" "INFO"
        medet "${METEOR_OUTPUT}/${3}.dec" "${NOAA_OUTPUT}/images/${3}-122" -r 65 -g 65 -b 64 -d
    fi

    log "Rectifying image to adjust aspect ratio" "INFO"
    python3 "${NOAA_HOME}/rectify.py" "${NOAA_OUTPUT}/images/${3}-122.bmp"
    convert "${NOAA_OUTPUT}/images/${3}-122-rectified.jpg" -channel rgb -normalize -undercolor black -fill yellow -pointsize 60 -annotate +20+60 "${1} ${START_DATE} Elev: $7°" "${NOAA_OUTPUT}/images/${3}-122-rectified.jpg"
    /usr/bin/convert -thumbnail 300 "${NOAA_OUTPUT}/images/${3}-122-rectified.jpg" "${NOAA_OUTPUT}/images/thumb/${3}-122-rectified.jpg"
    rm "${NOAA_OUTPUT}/images/${3}-122.bmp"
    rm "${METEOR_OUTPUT}/${3}.bmp"
    rm "${METEOR_OUTPUT}/${3}.dec"

    sqlite3 $HOME/raspberry-noaa/panel.db "insert into decoded_passes (pass_start, file_path, daylight_pass, sat_type) values ($5,\"$3\", 1,0);"
    pass_id=$(sqlite3 $HOME/raspberry-noaa/panel.db "select id from decoded_passes order by id desc limit 1;")
    sqlite3 $HOME/raspberry-noaa/panel.db "update predict_passes set is_active = 0 where (predict_passes.pass_start) in (select predict_passes.pass_start from predict_passes inner join decoded_passes on predict_passes.pass_start = decoded_passes.pass_start where decoded_passes.id = $pass_id);"

    if [ -n "$CONSUMER_KEY" ]; then
        log "Posting to Twitter" "INFO"
        python3 "${NOAA_HOME}/post.py" "$1 ${START_DATE} Resolución completa: https://weather.reyni.co/detail.php?id=$pass_id" "$7" "${NOAA_OUTPUT}/images/${3}-122-rectified.jpg"
    fi
else
    log "Decoding failed, either a bad pass/low SNR or a software problem" "ERROR"
    sqlite3 $HOME/raspberry-noaa/panel.db "update predict_passes set is_active = 0 where predict_passes.pass_start = $5;"
fi
