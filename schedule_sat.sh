#!/bin/bash

### Run as a normal user
if [ $EUID -eq 0 ]; then
    echo "This script shouldn't be run as root."
    exit 1
fi

## import common lib
. "$HOME/.noaa.conf"
. "$NOAA_HOME/common.sh"

# $1 = Satellite Name
# $2 = Frequency
# $3 = FileName base
# $4 = TLE File
# $5 = EPOC start time
# $6 = Time to capture
# $7 = Satellite max elevation

if [[ "$1" == *"NOAA"* ]]; then
	receive_script="receive_noaa"
elif [[ "$1" == *"METEOR"* ]]; then
	receive_script="receive_meteor"
else
	log "No recognized receive skript for satellite $1!" ERROR
	return -1
fi

log "Looking for passes of $1" INFO

PREDICTION_START=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" | head -1)
PREDICTION_END=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" | tail -1)

if [ -z "$PREDICTION_START" ]; then
	log "predict did not return any values for $1!" ERROR
	log "predict -t \"${NOAA_HOME}\"/predict/weather.tle -p \"${1}\"" ERROR
	predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" >> /var/log/noaa.log 2>&1
fi

var2=$(echo "${PREDICTION_END}" | cut -d " " -f 1)

MAXELEV=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" | awk -v max=0 '{if($5>max){max=$5}}END{print max}')

while [ "$(date --date="@${var2}" +%D)" = "$(date +%D)" ]; do
	START_TIME=$(echo "$PREDICTION_START" | cut -d " " -f 3-4)
	var1=$(echo "$PREDICTION_START" | cut -d " " -f 1)
	var3=$(echo "$START_TIME" | cut -d " " -f 2 | cut -d ":" -f 3)
	TIMER=$(expr "${var2}" - "${var1}" + "${var3}")
	OUTDATE=$(date --date="TZ=\"UTC\" ${START_TIME}" +%Y%m%d-%H%M%S)

	if [ "${MAXELEV}" -gt "${SAT_MIN_ELEV}" ]; then
		SATNAME=$(echo "$1" | sed "s/ //g")
		log "Scheduling ${SATNAME} at ${OUTDATE} $MAXELEV" INFO
		echo "${NOAA_HOME}/${receive_script}.sh \"${1}\" $2 ${SATNAME}-${OUTDATE} "${NOAA_HOME}"/predict/weather.tle \
${var1} ${TIMER} ${MAXELEV}" | at "$(date --date="TZ=\"UTC\" ${START_TIME}" +"%H:%M %D")"
		sqlite3 $HOME/raspberry-noaa/panel.db "insert or replace into predict_passes (sat_name,pass_start,pass_end,max_elev,is_active) values (\"$SATNAME\",$var1,$var2,$MAXELEV, 1);"
	else
		log "Max. elevation ${MAXELEV} too small for configured ${SAT_MIN_ELEV}" DEBUG
	fi
	NEXTPREDICT=$(expr "${var2}" + 60)
	PREDICTION_START=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" "${NEXTPREDICT}" | head -1)
	PREDICTION_END=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}"  "${NEXTPREDICT}" | tail -1)
	MAXELEV=$(predict -t "${NOAA_HOME}"/predict/weather.tle -p "${1}" "${NEXTPREDICT}" | awk -v max=0 '{if($5>max){max=$5}}END{print max}')
	var2=$(echo "${PREDICTION_END}" | cut -d " " -f 1)
done

