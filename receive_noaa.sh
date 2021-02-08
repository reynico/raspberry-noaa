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


## pass start timestamp and sun elevation
PASS_START=$(expr "$5" + 90)
SUN_ELEV=$(python3 "$NOAA_HOME"/sun.py "$PASS_START")

if pgrep "rtl_fm" > /dev/null
then
	log "There is an existing rtl_fm instance running, I quit" "ERROR"
	exit 1
fi

# $1 = Satellite Name
# $2 = Frequency
# $3 = FileName base
# $4 = TLE File
# $5 = EPOC start time
# $6 = Time to capture
# $7 = Satellite max elevation

pre_samplerate=60k

log "Starting rtl_fm record for $1 at $2 to $3 at epoch $5" "INFO"
log "timeout ${6} /usr/local/bin/rtl_fm ${BIAS_TEE} -f ${2}M -s$pre_samplerate $GAIN -p $PPM_ERROR -E wav -E deemp -F 0 - | /usr/bin/sox -t raw -e signed -c 1 -b 16 -r $pre_samplerate - ${RAMFS_AUDIO}/audio/${3}.wav rate 11025" DEBUG
timeout "${6}" /usr/local/bin/rtl_fm ${BIAS_TEE} -f "${2}"M -s$pre_samplerate $GAIN -p $PPM_ERROR -E wav -E deemp -F 0 - | /usr/bin/sox -t raw -e signed -c 1 -b 16 -r $pre_samplerate - "${RAMFS_AUDIO}/audio/${3}.wav" rate 11025

if [ "${SUN_ELEV}" -gt "${SUN_MIN_ELEV}" ]; then
	ENHANCEMENTS="ZA MCIR MCIR-precip MSA MSA-precip HVC-precip HVCT-precip HVC HVCT"
	daylight="true"
else
	ENHANCEMENTS="ZA MCIR MCIR-precip"
	daylight="false"
fi

log "Bulding pass map wxtoimg" "INFO"
/usr/local/bin/wxmap -T "${1}" -H "${4}" -p 0 -l 0 -o "${PASS_START}" "${NOAA_HOME}/map/${3}-map.png"
for i in $ENHANCEMENTS; do
	log "Decoding image" "INFO"
	/usr/local/bin/wxtoimg -o -m "${NOAA_HOME}/map/${3}-map.png" -e "$i" "${RAMFS_AUDIO}/audio/${3}.wav" "${NOAA_OUTPUT}/images/${3}-$i.jpg"
	/usr/bin/convert -quality 98 -format jpg "${NOAA_OUTPUT}/images/${3}-$i.jpg" -undercolor black -fill yellow -pointsize 18 -annotate +20+20 "${1} $i ${START_DATE} Elev: $7°" "${NOAA_OUTPUT}/images/${3}-$i.jpg"
	/usr/bin/convert -thumbnail 300 "${NOAA_OUTPUT}/images/${3}-$i.jpg" "${NOAA_OUTPUT}/images/thumb/${3}-$i.jpg"
done

log "Building noaa-apt maps" DEBUG
curpath=$(pwd) # needed for faulty noaa-apt arm version
cd /usr/bin
noaa-apt "${RAMFS_AUDIO}/audio/${3}.wav" -R auto -m yes -o "${NOAA_OUTPUT}/images/${3}-noaa-apt.png"
cd $curpath
/usr/bin/convert -quality 98 -format jpg "${NOAA_OUTPUT}/images/${3}-noaa-apt.png" -undercolor black -fill yellow -pointsize 18 -annotate +20+20 "${1} $i ${START_DATE} Elev: $7°" "${NOAA_OUTPUT}/images/${3}-noaa-apt.jpg"
/usr/bin/convert -thumbnail 300 "${NOAA_OUTPUT}/images/${3}-noaa-apt.jpg" "${NOAA_OUTPUT}/images/thumb/${3}-noaa-apt.jpg"

rm "${NOAA_OUTPUT}/images/${3}-noaa-apt.png"
rm "${NOAA_HOME}/map/${3}-map.png"

if [ "${SUN_ELEV}" -gt "${SUN_MIN_ELEV}" ]; then
	sqlite3 $HOME/raspberry-noaa/panel.db "insert into decoded_passes (pass_start, file_path, daylight_pass, sat_type) values ($5,\"$3\", 1,1);"
else
	sqlite3 $HOME/raspberry-noaa/panel.db "insert into decoded_passes (pass_start, file_path, daylight_pass, sat_type) values ($5,\"$3\", 0,1);"
fi

pass_id=$(sqlite3 $HOME/raspberry-noaa/panel.db "select id from decoded_passes order by id desc limit 1;")

if [ -n "$CONSUMER_KEY" ]; then
	log "Posting to Twitter" "INFO"
	if [ "${SUN_ELEV}" -gt "${SUN_MIN_ELEV}" ]; then
		python3 "${NOAA_HOME}/post.py" "$1 ${START_DATE} Mas imagenes: https://weather.reyni.co/detail.php?id=$pass_id" "$7" "${NOAA_OUTPUT}/images/$3-MCIR-precip.jpg" "${NOAA_OUTPUT}/images/$3-MSA-precip.jpg" "${NOAA_OUTPUT}/images/$3-HVC-precip.jpg" "${NOAA_OUTPUT}/images/$3-HVCT-precip.jpg"
	else
		python3 "${NOAA_HOME}/post.py" "$1 ${START_DATE} Mas imagenes: https://weather.reyni.co/detail.php?id=$pass_id" "$7" "${NOAA_OUTPUT}/images/$3-MCIR-precip.jpg" "${NOAA_OUTPUT}/images/$3-MCIR.jpg"
	fi
fi

sqlite3 $HOME/raspberry-noaa/panel.db "update predict_passes set is_active = 0 where (predict_passes.pass_start) in (select predict_passes.pass_start from predict_passes inner join decoded_passes on predict_passes.pass_start = decoded_passes.pass_start where decoded_passes.id = $pass_id);"

if [ "$DELETE_AUDIO" = true ]; then
	log "Deleting audio files" "INFO"
  rm "${RAMFS_AUDIO}/audio/${3}.wav"
else
	log "Moving audio files out to the SD card" "INFO"
  mv "${RAMFS_AUDIO}/audio/${3}.wav" "${NOAA_OUTPUT}/audio/${3}_${pre_samplerate}_${7}.wav"
fi
