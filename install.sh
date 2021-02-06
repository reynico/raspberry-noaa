#!/bin/bash
set -e

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

die() {
    >&2 echo "${RED}error: $1${RESET}" && exit 1
}

log() {
    echo "$*"
}

log_done() {
    echo " ${GREEN}✓${RESET} $1"
}

log_running() {
    echo " ${YELLOW}*${RESET} $1"
}

log_error() {
    echo " ${RED}error: $1${RESET}"
}

success() {
    echo "${GREEN}$1${RESET}"
}

### Run as a normal user
if [ $EUID -eq 0 ]; then
    die "This script shouldn't be run as root."
fi

### Verify cloned repo
if [ ! -e "$HOME/raspberry-noaa" ]; then
    die "Is https://github.com/reynico/raspberry-noaa cloned in your home directory?"
fi

### Install required packages
log_running "Installing required packages..."

raspbian_version="$(lsb_release -c --short)"

if [ "$raspbian_version" == "stretch" ]; then
    wget -q https://packages.sury.org/php/apt.gpg -O- | sudo apt-key add -
    echo "deb https://packages.sury.org/php/ stretch main" | sudo tee /etc/apt/sources.list.d/php7.list
fi

sudo apt update -yq
sudo apt install -yq python-setuptools \
		     unzip zip \
                     cmake \
                     libusb-1.0-0-dev \
                     sox libsox-fmt-mp3 \
                     at \
                     bc \
                     nginx \
                     libncurses5-dev \
                     libncursesw5-dev \
                     libatlas-base-dev \
                     python3-pip \
                     imagemagick \
                     libxft-dev \
                     libxft2 \
                     libjpeg9 \
                     libjpeg9-dev \
                     socat \
                     php7.3-fpm \
                     php7.3-sqlite3 \
                     sqlite3

if [ "$raspbian_version" == "stretch" ]; then
    sudo apt install -yq libgfortran-5-dev
else
    sudo apt install -yq libgfortran5
fi

sudo python3 -m pip install numpy ephem tweepy Pillow
log_done "Packages installed"

### Create the database schema
if [ -e "$HOME/raspberry-noaa/panel.db" ]; then
    log_done "Database already created"
else
    sqlite3 "panel.db" < "templates/webpanel_schema.sql"
    log_done "Database schema created"
fi

### Blacklist DVB modules
if [ -e /etc/modprobe.d/rtlsdr.conf ]; then
    log_done "DVB modules were already blacklisted"
else
    sudo cp templates/modprobe.d/rtlsdr.conf /etc/modprobe.d/rtlsdr.conf
    log_done "DVB modules are blacklisted now"
fi

### Install RTL-SDR
if [ -e /usr/local/bin/rtl_fm ]; then
    log_done "rtl-sdr was already installed"
else
    log_running "Installing rtl-sdr from librtlsdr..."
    (
        cd /tmp/
        git clone https://github.com/librtlsdr/librtlsdr.git
        cd librtlsdr/
        mkdir build
        cd build
        cmake ../ -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON
        make
        sudo make install
        sudo ldconfig
        cd /tmp/
        sudo cp ./rtl-sdr/rtl-sdr.rules /etc/udev/rules.d/
    )
    log_done "rtl-sdr install done"
fi

### Install WxToIMG
if [ -e /usr/local/bin/xwxtoimg ]; then
    log_done "WxToIMG was already installed"
else
    log_running "Installing WxToIMG..."
    sudo dpkg -i software/wxtoimg-armhf-2.11.2-beta.deb
    log_done "WxToIMG installed"
fi

### install predict
if command -v predict &> /dev/null; then
    log_done "predict was already installed"
else
    $orig_dir=$(pwd)
    cd software
    tar -xzf predict-2.2.7.tar.gz
    cd predict-2.2.7
    sudo ./configure	#this also installs :X
    cd $orig_dir
    log_done "predict installed"
fi

### Install default config file
if [ -e "$HOME/.noaa.conf" ]; then
    log_done "$HOME/.noaa.conf already exists"
else
    cp "templates/noaa.conf" "$HOME/.noaa.conf"
    log_done "$HOME/.noaa.conf installed"
fi

if [ -d "$HOME/.predict" ] && [ -e "$HOME/.predict/predict.qth" ]; then
    log_done "$HOME/.predict/predict.qth already exists"
else
    mkdir "$HOME/.predict"
    cp "templates/predict.qth" "$HOME/.predict/predict.qth"
    log_done "$HOME/.predict/predict.qth installed"
fi

if [ -e "$HOME/.wxtoimgrc" ]; then
    log_done "$HOME/.wxtoimgrc already exists"
else
    cp "templates/wxtoimgrc" "$HOME/.wxtoimgrc"
    log_done "$HOME/.wxtoimgrc installed"
fi

if [ -e "$HOME/.tweepy.conf" ]; then
    log_done "$HOME/.tweepy.conf already exists"
else
    cp "templates/tweepy.conf" "$HOME/.tweepy.conf"
    log_done "$HOME/.tweepy.conf installed"
fi

### Install meteor_demod
if [ -e /usr/bin/meteor_demod ]; then
    log_done "meteor_demod was already installed"
else
    log_running "Installing meteor_demod..."
    (
        cd /tmp
        git clone https://github.com/dbdexter-dev/meteor_demod.git
        cd meteor_demod
        make
        sudo make install
    )
    log_done "meteor_demod installed"
fi

### Install medet_arm
if [ -e /usr/bin/medet ]; then
    log_done "medet was already installed"
else
    if [[ $(uname -m) == *"arm"* ]]; then
        log_running "Installing medet_arm..."
        sudo cp software/medet_arm /usr/bin/medet
    elif [[ $(uname -m) == *"x86_64"* ]]; then
        log_running "Installing medet_x86_64..."
        sudo cp software/medet_x86_64 /usr/bin/medet
    else
	log_error "Unknown archictecture $(uname -m)!"
        exit -1
    fi
    sudo chmod +x /usr/bin/medet
    log_done "medet installed"
fi

### Install noaa-apt
if command -v noaa-apt &> /dev/null; then
    log_done "noaa-apt was already installed"
else
    if [[ $(uname -m) == *"arm"* ]]; then
        log_running "Installing noaa-apt arm..."
        unzip software/noaa-apt-1.3.0-armv7-linux-gnueabihf-nogui.zip
        sudo mv noaa-apt /usr/bin
	sudo mv res /usr/bin 	#ok, this is not so nice, but it works
    elif [[ $(uname -m) == *"x86_64"* ]]; then
        log_running "Installing noaa-apt x86..."
        sudo dpkg -i software/noaa-apt_1.3.0-1_amd64.deb
    else
	log_error "Unknown archictecture $(uname -m)!"
        exit -1
    fi
    log_done "noaa-apt installed"
fi


### Cron the scheduler
set +e
crontab -l | grep -q "raspberry-noaa"
if [ $? -eq 0 ]; then
    log_done "Crontab for schedule.sh already exists"
else
    cat <(crontab -l) <(echo "1 0 * * * $HOME/raspberry-noaa/schedule.sh") | crontab -
    log_done "Crontab installed"
fi
set -e

### Setup Nginx
log_running "Setting up Nginx..."
usr=$(whoami)
sudo cp templates/nginx.cfg /etc/nginx/sites-enabled/default
(
    sudo mkdir -p /var/www/wx/images
    sudo chown -R $usr:$usr /var/www/wx
    sudo usermod -a -G www-data $usr
    sudo chmod 775 /var/www/wx
)
sudo systemctl restart nginx
sudo cp -rp templates/webpanel/* /var/www/wx/
sed -i -e "s/pi/${usr}/g" "/var/www/wx/Model/Conn.php"
log_done "Nginx configured"

### Setup ramFS
SYSTEM_MEMORY=$(free -m | awk '/^Mem:/{print $2}')
if [ "$SYSTEM_MEMORY" -lt 2000 ]; then
	sed -i -e "s/1000M/200M/g" templates/fstab
fi
set +e
cat /etc/fstab | grep -q "ramfs"
if [ $? -eq 0 ]; then
    log_done "ramfs already setup"
else
    sudo mkdir -p /var/ramfs
    cat templates/fstab | sudo tee -a /etc/fstab > /dev/null
    log_done "Ramfs installed"
fi
sudo mount -a
sudo chmod 777 /var/ramfs
set -e

if [ -f "$HOME/raspberry-noaa/demod.py" ]; then
    log_done "pd120_decoder already installed"
else
    wget -qr https://github.com/reynico/pd120_decoder/archive/master.zip -O /tmp/master.zip
    (
        cd /tmp
        unzip master.zip
        cd pd120_decoder-master/pd120_decoder/
        python3 -m pip install --user -r requirements.txt
        cp demod.py utils.py "$HOME/raspberry-noaa/"
    )
    log_done "pd120_decoder installed"
fi


success "Install (almost) done!"

read -rp "Do you want to enable bias-tee? (y/N)"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sed -i -e "s/enable_bias_tee/-T/g" "$HOME/.noaa.conf"
    log_done "Bias-tee is enabled!"
else
    sed -i -e "s/enable_bias_tee//g" "$HOME/.noaa.conf"
fi

echo "
    Next we'll configure your webpanel language
    and locale settings - you can update these in the
    future by modifying 'lang' in /var/www/wx/Config.php
    and 'date_default_timezone_set' in /var/www/wx/header.php
    "

# language configuration
langs=($(find templates/webpanel/language/ -type f -printf "%f\n" | cut -f 1 -d '.'))
while : ; do
    read -rp "Enter your preferred language (${langs[*]}): "
    lang=$REPLY

    if [[ ! " ${langs[@]} " =~ " ${lang} " ]]; then
        log_error "choice $lang is not one of the available options (${langs[*]})"
    else
        break
    fi
done
sed -i -e "s/'lang' => '.*'$/'lang' => '${lang}'/" "/var/www/wx/Config.php"

echo "Visit https://www.php.net/manual/en/timezones.php for a list of available timezones"
read -rp "Enter your preferred timezone: "
    timezone=$REPLY
timezone=$(echo $timezone | sed 's/\//\\\//g')
sed -i -e "s/date_default_timezone_set('.*');/date_default_timezone_set('${timezone}');/" "/var/www/wx/header.php"

echo "
    It's time to configure your ground station
    You'll be asked for your latitude and longitude
    Use negative values for South and West
    "

read -rp "Enter your latitude (South values are negative): "
    lat=$REPLY

read -rp "Enter your longitude (West values are negative): "
    lon=$REPLY

# note: this can probably be improved by calculating this
# automatically - good for a future iteration
read -rp "Enter your timezone offset (ex: -3 for Argentina time): "
    tzoffset=$REPLY

sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g;s/pi/${usr}/g" "$HOME/.noaa.conf"
sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g" "$HOME/.wxtoimgrc"
sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g" "$HOME/.predict/predict.qth"
sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g;s/change_tz/$(echo  "$tzoffset * -1" | bc)/g" "sun.py"

success "Install done! Double check your $HOME/.noaa.conf settings"

echo "
    If you want to post your images to Twitter, please setup
    your Twitter credentials on $HOME/.tweepy.conf
"

set +e

### Running WXTOIMG to have the user accept the licensing agreement
wxtoimg

read -rp "reboot now? (Y/n)"
    doreboot=$REPLY

[ ! -z "$doreboot" ] || sudo reboot
[ "$doreboot" == "y" ] && sudo reboot
