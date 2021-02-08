#!/bin/bash

### Run as a normal user
if [ $EUID -eq 0 ]; then
    echo "This script shouldn't be run as root."
    exit 1
fi

## import common lib
. "$HOME/.noaa.conf"
. "$NOAA_HOME/common.sh"

log "Scheduling new passes" INFO

wget -qr http://www.celestrak.com/NORAD/elements/weather.txt -O "${NOAA_HOME}"/predict/weather.txt
wget -qr http://www.celestrak.com/NORAD/elements/amateur.txt -O "${NOAA_HOME}"/predict/amateur.txt
grep "NOAA 15" "${NOAA_HOME}"/predict/weather.txt -A 2 > "${NOAA_HOME}"/predict/weather.tle
grep "NOAA 18" "${NOAA_HOME}"/predict/weather.txt -A 2 >> "${NOAA_HOME}"/predict/weather.tle
grep "NOAA 19" "${NOAA_HOME}"/predict/weather.txt -A 2 >> "${NOAA_HOME}"/predict/weather.tle
grep "METEOR-M 2" "${NOAA_HOME}"/predict/weather.txt -A 2 >> "${NOAA_HOME}"/predict/weather.tle
grep "METEOR-M2 2" "${NOAA_HOME}"/predict/weather.txt -A 2 >> "${NOAA_HOME}"/predict/weather.tle
if [ "$SCHEDULE_ISS" == "true" ]; then
    grep "ZARYA" "${NOAA_HOME}"/predict/amateur.txt -A 2 > "${NOAA_HOME}"/predict/amateur.tle
fi

#Remove all AT jobs
for i in $(atq | awk '{print $1}');do atrm "$i";done

#Schedule Satellite Passes:
if [ "$SCHEDULE_ISS" == "true" ]; then
    "${NOAA_HOME}"/schedule_iss.sh "ISS (ZARYA)" 145.8000
fi
"${NOAA_HOME}"/schedule_sat.sh "METEOR-M 2" 137.1000
#"${NOAA_HOME}"/schedule_sat.sh "METEOR-M2 2" 137.9000	#Meteor M2-2 will never send LRPT again :(
"${NOAA_HOME}"/schedule_sat.sh "NOAA 19" 137.1000
"${NOAA_HOME}"/schedule_sat.sh "NOAA 18" 137.9125
"${NOAA_HOME}"/schedule_sat.sh "NOAA 15" 137.6200
