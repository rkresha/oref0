#!/bin/bash

# This script sets up an openaps environment to work with loop.sh,
# by defining the required devices, reports, and aliases.
#
# Released under MIT license. See the accompanying LICENSE.txt file for
# full terms and conditions
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# functions
die() {
  printf '%s\n' "$@"
  exit 1
}

# The uninstall function locates the manifest file and removes the src and openaps home directory. This function does not check for internet connectivity and only support ones openaps directory.
uninstall() {
    if [[ -f ${manifest} ]]; then
        # SRC=$(awk -F'[:]' '$1 ~ /^SRC.*/ { print $2 }' ${manifest})
        # OPENAPS_HOME=$(awk -F'[:]' '$1 ~ /^OPENAPS_HOME.*/ { print $2 }' ${manifest})
        SRC=$(json -a src < ${manifest})
        OPENAPS_HOME=$(json -a openaps < ${manifest})
        if [[ -d ${SRC} ]]; then
            if [[ -d ${OPENAPS_HOME} ]]; then
                rm -rf ${SRC}
                rm -rf ${OPENAPS_HOME}
            else
                die "Unable to uninstall because of ${OPENAPS_HOME} is missing"
            fi
        else
            die "Unable to uninstall because of ${SRC} is missing"
        fi
    else
        die "Unable to locate a record of a previous install"
    fi
    crontab -l | awk -v ref="$(basename ${OPENAPS_HOME})" '$0 !~ ref && !/wpa_cli|NIGHTSCOUT|API_SECRET|killall/' | crontab -
    crontab -l
    rm ${manifest}
    killall -g openaps
    
}

# The refresh function checks for internet connectivity and then removes the {openaps,src} directory and removes crontab entries
refresh() {
if [[ $(ping -c1 google.com > /dev/null 2>&1; printf '%s\n' "$?") -eq 0 ]]; then
    if [[ -z ${REPO} ]]; then
        read -p "Which github repo would you like to use? [git://github.com/openaps/oref0.git#dev]: " -r
        if ! [[ ${REPLY:-git://github.com/openaps/oref0.git#dev} =~ ^git.* ]]; then
            REPO=git://github.com/openaps/oref0.git#dev
        else
            REPO=${REPLY}
        fi
        printf '%s\n' "${REPO}"
        cd ${HOME} || die "Can't cd ${HOME}"
        sudo npm install -g ${REPO} && uninstall && setup
    else
        sudo npm install -g ${REPO} && uninstall && setup
    fi
fi
}

setup() {
    # Prerequisites
    
    # curl -s https://raw.githubusercontent.com/openaps/docs/master/scripts/quick-packages.sh | bash -
    # Enhance the quick-packages.sh to upgrade components and autoremove
    curl -s https://raw.githubusercontent.com/openaps/docs/master/scripts/quick-packages.sh | awk '{ gsub(/^sudo apt-get update \&\& sudo apt-get -y upgrade/, "sudo apt-get update \&\& sudo apt-get -y --with-new-pkgs upgrade \&\& sudo apt-get autoremove"); print }' | bash -
    

    # Main 
    if ! [[ ${CGM,,} =~ "g4" || ${CGM,,} =~ "g5" || ${CGM,,} =~ "mdt" || ${CGM,,} =~ "shareble" ]]; then
        printf '%s\n' "Unsupported CGM.  Please select (Dexcom) G4 (default), shareble, G5, or MDT."
        printf '%s\n' "If you'd like to help add Medtronic CGM support, please contact @scottleibrand on Gitter"
        printf "\n"
        DIR="" # to force a Usage prompt
    fi
    if ! ( git config -l | grep -q user.email ) ; then
        read -p "What email address would you like to use for git commits? " -r
        EMAIL=${REPLY}
        git config --global user.email ${EMAIL}
    fi
    if ! ( git config -l | grep -q user.name ); then
        read -p "What full name would you like to use for git commits? " -r
        NAME=${REPLY}
        git config --global user.name ${NAME}
    fi
    if [[ -z "${DIR}" || -z "${serial}" || -z "${REPO}" ]]; then
        printf '%s\n' "Usage: oref0-setup.sh <--dir=directory> <--serial=pump_serial_#> [--tty=/dev/ttySOMETHING] [--max_iob=0] [--ns-host=https://mynightscout.azurewebsites.net] [--api-secret=myplaintextsecret] [--option=(setup|refresh|uninstall)] [--cgm=(G4|shareble|G5|MDT)] [--enable='autosens meal']"
        read -p "Start interactive setup? [Y]/n " -r
        if [[ ${REPLY:-Y} =~ ^[Nn]$ ]]; then
            exit
        fi
        cd ${HOME} || die "Can't cd into ${HOME}"
        read -p "What would you like to call your loop directory? [myopenaps] " -r
        DIR=${REPLY}
        if [[ -z ${DIR} ]]; then DIR="myopenaps"; fi
        printf '%s\n' "Ok, ${DIR} it is."
        directory="$(readlink -m ${DIR})"
        read -p "What is your pump serial number (numbers only)? " -r
        serial=${REPLY}
        printf '%s\n' "Ok, ${serial} it is."
        read -p "What kind of CGM are you using? (i.e. G4, shareble, G5, MDT) " -r
        CGM=${REPLY}
        printf '%s\n' "Ok, ${CGM} it is."
        if [[ ${CGM,,} =~ "shareble" ]]; then
            read -p "What is your G4 Share Serial Number? (i.e. SM12345678) " -r
            BLE_SERIAL=${REPLY}
            printf '%s\n' "${BLE_SERIAL}? Got it."
        fi
        read -p "Are you using mmeowlink? If not, press enter. If so, what TTY port (i.e. /dev/ttySOMETHING)? " -r
        ttyport=${REPLY}
        printf '%s' "Ok, "
        if [[ -z ${ttyport} ]]; then
            printf '%s' Carelink
        else
            printf '%s' TTY ${ttyport}
        fi
        printf '%s\n' " it is."
        printf '%s\n' Are you using Nightscout? If not, press enter.
        read -p "If so, what is your Nightscout host? (i.e. https://mynightscout.azurewebsites.net)? " -r
        NIGHTSCOUT_HOST=${REPLY}
        if [[ -z ${NIGHTSCOUT_HOST} ]]; then
            printf '%s\n' "Ok, no Nightscout for you."
        else
            printf '%s\n' "Ok, ${NIGHTSCOUT_HOST} it is."
        fi
        if ! [[ -z ${NIGHTSCOUT_HOST} ]]; then
            read -p "And what is your Nightscout api secret (i.e. myplaintextsecret)? " -r
            API_SECRET=${REPLY}
            printf '%s\n' "Ok, ${API_SECRET} it is."
        fi
        read -p "Do you need any advanced features? [Y]/n " -r
        if ! [[ ${REPLY:-Y} =~ ^[Nn]$ ]]; then
            read -p "Enable automatic sensitivity adjustment? [Y]/n " -r
            if ! [[ ${REPLY:-Y} =~ ^[Nn]$ ]]; then
                ENABLE+=" autosens "
            fi
            read -p "Enable advanced meal assist? [Y]/n " -r
            if ! [[ ${REPLY:-Y} =~ ^[Nn]$ ]]; then
                ENABLE+=" meal "
            fi
        fi
        read -p "Which github repo would you like to use? [git://github.com/openaps/oref0.git'#dev']" -r
        if ! [[ ${REPLY:-git://github.com/openaps/oref0.git'#dev'} =~ ^git ]]; then
            REPO=git://github.com/openaps/oref0.git'#dev'
        fi
    fi
    
    OPENAPS_HOME=${directory}
    printf '%s' "Setting up oref0 from ${REPO} in ${directory} for pump ${serial} with ${CGM} CGM, "
    if [[ ${CGM,,} =~ "shareble" ]]; then
        printf '%s' "G4 Share serial ${BLE_SERIAL}, "
    fi
    printf "\n"
    printf '%s' "NS host ${NIGHTSCOUT_HOST}, "
    if [[ -z ${ttyport} ]]; then
        printf '%s' Carelink
    else
        printf '%s' TTY ${ttyport}
    fi
    if [[ ${max_iob} -ne 0 ]]; then printf '%s' ", max_iob ${max_iob}"; fi
        if [[ ! -z ${ENABLE} ]]; then printf '%s' ", advanced features ${ENABLE}"; fi
        printf "\n"

        if [[ -z ${HEADLESS} ]]; then
            read -p "Continue? y/[N] " -r
        fi
        if [[ ${REPLY:-N} =~ ^[Yy]$ ]] || ! [[ -z ${HEADLESS} ]]; then

        printf '%s' "Checking ${directory}: "
        mkdir -p ${directory}
        if ( cd ${directory} && git status 2>/dev/null >/dev/null && openaps use -h >/dev/null && printf '%s\n' "true" ); then
            printf '%s\n' "${directory} already exists"
        elif openaps init ${directory}; then
            printf '%s\n' "${directory} initialized"
        else
            die "Can't init ${directory}"
        fi
        cd ${directory} || die "Can't cd ${directory}"
        ls monitor 2>/dev/null >/dev/null || mkdir monitor || die "Can't mkdir monitor"
        ls raw-cgm 2>/dev/null >/dev/null || mkdir raw-cgm || die "Can't mkdir raw-cgm"
        ls cgm 2>/dev/null >/dev/null || mkdir cgm || die "Can't mkdir cgm"
        ls settings 2>/dev/null >/dev/null || mkdir settings || die "Can't mkdir settings"
        ls enact 2>/dev/null >/dev/null || mkdir enact || die "Can't mkdir enact"
        ls upload 2>/dev/null >/dev/null || mkdir upload || die "Can't mkdir upload"

        SRC=${HOME}/src
        mkdir -p ${SRC}
        if [ -d ${SRC}/oref0/ ]; then
            printf '%s\n' "${SRC}/oref0/ already exists; pulling latest"
            (cd ${SRC}/oref0 && git fetch && git pull) || die "Couldn't pull latest oref0"
        else
            printf '%s' "Cloning $(awk -F'[/#.'']' '{print $5"/"$6" "$8":"}' <<< ${REPO}) "
            (cd ~/src && git clone -b $(awk -F'[/#.]' '{print $8" "$1"//"$2$3"."$4"/"$5"/"$6".git"}' <<< ${REPO})) || die "Couldn't clone $(awk -F'[/#.'']' '{print $6" "$8}' <<< ${REPO})"
        fi
        printf '%s\n' "Checking oref0 installation"
        ( grep -q oref0_glucose_since $(which nightscout) && oref0-get-profile --exportDefaults 2>/dev/null >/dev/null ) && (printf '%s\n' "Installing latest oref0 $(awk -F'[/#.]' '{print $8}' <<< ${REPO})" && cd ${SRC}/oref0/ && npm run global-install)

        printf '%s\n' "Checking mmeowlink installation"
        if openaps vendor add --path . mmeowlink.vendors.mmeowlink 2>&1 | grep "No module"; then
            if [ -d "${SRC}/mmeowlink/" ]; then
                printf '%s\n' "${SRC}/mmeowlink/ already exists; pulling latest dev branch"
                (cd ~/src/mmeowlink && git fetch && git checkout dev && git pull) || die "Couldn't pull latest mmeowlink dev"
            else
                printf '%s' "Cloning mmeowlink dev: "
                (cd ~/src && git clone -b dev git://github.com/oskarpearson/mmeowlink.git) || die "Couldn't clone mmeowlink dev"
            fi
            printf '%s\n' "Installing latest mmeowlink dev" && cd ${SRC}/mmeowlink/ && sudo pip install -e . || die "Couldn't install mmeowlink"
        fi

        cd ${directory} || die "Can't cd ${directory}"
        if [[ ${max_iob} -eq 0 ]]; then
            oref0-get-profile --exportDefaults > preferences.json || die "Could not run oref0-get-profile"
        else
            printf '%s\n' "{ \"max_iob\": ${max_iob} }" > max_iob.json && oref0-get-profile --updatePreferences max_iob.json > preferences.json && rm max_iob.json || die "Could not run oref0-get-profile"
        fi

        cat preferences.json
        git add preferences.json

        # enable log rotation
        sudo cp ${SRC}/oref0/logrotate.openaps /etc/logrotate.d/openaps || die "Could not cp /etc/logrotate.d/openaps"
        #sudo cp ${SRC}/oref0/logrotate.rsyslog /etc/logrotate.d/rsyslog || die "Could not cp /etc/logrotate.d/rsyslog"

        test -d /var/log/openaps || sudo mkdir /var/log/openaps && sudo chown ${USER} /var/log/openaps || die "Could not create /var/log/openaps"

        # configure ns
        if [[ ! -z "${NIGHTSCOUT_HOST}" && ! -z "${API_SECRET}" ]]; then
            printf '%s\n' "Removing any existing ns device: "
            killall -g openaps 2>/dev/null; openaps device remove ns 2>/dev/null
            printf '%s\n' "Running nightscout autoconfigure-device-crud ${NIGHTSCOUT_HOST} ${API_SECRET}"
            nightscout autoconfigure-device-crud ${NIGHTSCOUT_HOST} ${API_SECRET} || die "Could not run nightscout autoconfigure-device-crud"
        fi

        # import template
        for type in vendor device report alias; do
            printf '%s\n' "importing ${type} file"
            openaps import < ${SRC}/oref0/lib/oref0-setup/${type}.json || die "Could not import ${type}.json"
        done

        # add/configure devices
        if [[ ${CGM,,} =~ "g5" ]]; then
            openaps use cgm config --G5
            openaps report add raw-cgm/raw-entries.json JSON cgm oref0_glucose --hours "24.0" --threshold "100" --no-raw
        elif [[ ${CGM,,} =~ "shareble" ]]; then
            printf '%s\n' "Checking Adafruit_BluefruitLE installation"
            if ! python -c "import Adafruit_BluefruitLE" 2>/dev/null; then
                if [ -d "${SRC}/Adafruit_Python_BluefruitLE/" ]; then
                    printf '%s\n' "${SRC}/Adafruit_Python_BluefruitLE/ already exists; pulling latest master branch"
                    (cd ~/src/Adafruit_Python_BluefruitLE && git fetch && git checkout wip/bewest/custom-gatt-profile && git pull) || die "Couldn't pull latest Adafruit_Python_BluefruitLE wip/bewest/custom-gatt-profile"
                else
                    printf '%s' "Cloning Adafruit_Python_BluefruitLE wip/bewest/custom-gatt-profile: "
                    (cd ~/src && git clone -b wip/bewest/custom-gatt-profile https://github.com/bewest/Adafruit_Python_BluefruitLE.git) || die "Couldn't clone Adafruit_Python_BluefruitLE wip/bewest/custom-gatt-profile"
                fi
                printf '%s\n' "Installing Adafruit_BluefruitLE" && cd ${SRC}/Adafruit_Python_BluefruitLE && sudo python setup.py develop || die "Couldn't install Adafruit_BluefruitLE"
            fi
            if [ -d "${SRC}/openxshareble/" ]; then
                printf '%s\n' "${SRC}/openxshareble/ already exists; pulling latest master branch"
                (cd ~/src/openxshareble && git fetch && git checkout master && git pull) || die "Couldn't pull latest openxshareble master"
            else
                printf '%s' "Cloning openxshareble master: "
                (cd ~/src && git clone https://github.com/openaps/openxshareble.git) || die "Couldn't clone openxshareble master"
            fi
            printf '%s\n' "Checking openxshareble installation"
            if ! python -c "import openxshareble" 2>/dev/null; then
                printf '%s\n' "Installing openxshareble" && (cd ${SRC}/openxshareble && sudo python setup.py develop) || die "Couldn't install openxshareble"
            fi
            sudo apt-get -y install libusb-dev libdbus-1-dev libglib2.0-dev libudev-dev libical-dev libreadline-dev python-dbus || die "Couldn't apt-get install: run 'sudo apt-get update' and try again?"
            printf '%s\n' "Checking bluez installation"
            if ! bluetoothd --version | grep -q 5.37 2>/dev/null; then
                cd ${SRC} && wget https://www.kernel.org/pub/linux/bluetooth/bluez-5.37.tar.gz && tar xvfz bluez-5.37.tar.gz || die "Couldn't download bluez"
                cd ${SRC}/bluez-5.37 && ./configure --enable-experimental --disable-systemd && \
                make && sudo make install && sudo cp ./src/bluetoothd /usr/local/bin/ || die "Couldn't make bluez"
                sudo cp ${SRC}/openxshareble/bluetoothd.conf /etc/dbus-1/system.d/bluetooth.conf || die "Couldn't copy bluetoothd.conf"
                sudo killall bluetoothd; sudo /usr/local/bin/bluetoothd --experimental &
            fi
            openaps vendor add openxshareble || die "Couldn't add openxshareble vendor"
            openaps device remove cgm || die "Couldn't remove existing cgm device"
            openaps device add cgm openxshareble || die "Couldn't add openxshareble device"
            openaps use cgm configure --serial ${BLE_SERIAL} || die "Couldn't configure share serial"

        fi
        grep -q pump.ini .gitignore 2>/dev/null || printf '%s\n' "pump.ini" >> .gitignore
        git add .gitignore
        printf '%s\n' "Removing any existing pump device:"
        killall -g openaps 2>/dev/null; openaps device remove pump 2>/dev/null

        if [[ ${ttyport} =~ "spi" ]]; then
            printf '%s\n' "Checking spi_serial installation"
            if ! python -c "import spi_serial" 2>/dev/null; then
                if [ -d "${SRC}/915MHzEdisonExplorer_SW/" ]; then
                    printf '%s\n' "${SRC}/915MHzEdisonExplorer_SW/ already exists; pulling latest master branch"
                    (cd ~/src/915MHzEdisonExplorer_SW && git fetch && git checkout master && git pull) || die "Couldn't pull latest 915MHzEdisonExplorer_SW master"
                else
                    printf '%s' "Cloning 915MHzEdisonExplorer_SW master: "
                    (cd ~/src && git clone -b master https://github.com/EnhancedRadioDevices/915MHzEdisonExplorer_SW.git) || die "Couldn't clone 915MHzEdisonExplorer_SW master"
                fi
                printf '%s\n' "Installing spi_serial" && cd ${SRC}/915MHzEdisonExplorer_SW/spi_serial && sudo pip install -e . || die "Couldn't install spi_serial"
            fi

            printf '%s\n' "Checking mraa installation"
            if ! ldconfig -p | grep -q mraa; then
                printf '%s\n' "Installing swig etc."
                sudo apt-get install -y libpcre3-dev git cmake python-dev swig || die "Could not install swig etc."

                if [ -d "${SRC}/mraa/" ]; then
                    printf '%s\n' "${SRC}/mraa/ already exists; pulling latest master branch"
                    (cd ~/src/mraa && git fetch && git checkout master && git pull) || die "Couldn't pull latest mraa master"
                else
                    printf '%s' "Cloning mraa master: "
                    (cd ~/src && git clone -b master https://github.com/intel-iot-devkit/mraa.git) || die "Couldn't clone mraa master"
                fi
                ( cd ${SRC} && mkdir -p mraa/build && cd $_ && cmake .. -DBUILDSWIGNODE=OFF && \
                make && sudo make install && printf '\n%s\n\n' "mraa installed. Please reboot before using." ) || die "Could not compile mraa"
                sudo bash -c "grep -q i386-linux-gnu /etc/ld.so.conf || printf '%s\n' '/usr/local/lib/i386-linux-gnu/' >> /etc/ld.so.conf && ldconfig" || die "Could not update /etc/ld.so.conf"
            fi

        fi

        cd ${directory} || die "Can't cd ${directory}"
        if [[ -z ${ttyport} ]]; then
            openaps device add pump medtronic ${serial} || die "Can't add pump"
            # carelinks can't listen for silence or mmtune, so just do a preflight check instead
            openaps alias add wait-for-silence 'report invoke monitor/temp_basal.json'
            openaps alias add wait-for-long-silence 'report invoke monitor/temp_basal.json'
            openaps alias add mmtune 'report invoke monitor/temp_basal.json'
        else
            openaps device add pump mmeowlink subg_rfspy ${ttyport} ${serial} || die "Can't add pump"
            openaps alias add wait-for-silence '! bash -c "(mmeowlink-any-pump-comms.py --port '${ttyport}' --wait-for 1 | grep -q comms && printf Radio ok, || openaps mmtune) && printf \" Listening: \"; for i in $(seq 1 100); do printf .; mmeowlink-any-pump-comms.py --port '${ttyport}' --wait-for 30 2>/dev/null | egrep -v subg | egrep No && break; done"'
            openaps alias add wait-for-long-silence '! bash -c "printf \"Listening: \"; for i in $(seq 1 200); do printf .; mmeowlink-any-pump-comms.py --port '${ttyport}' --wait-for 45 2>/dev/null | egrep -v subg | egrep No && break; done"'
        fi

        # Medtronic CGM
        if [[ ${CGM,,} =~ "mdt" ]]; then
            sudo pip install -U openapscontrib.glucosetools || die "Couldn't install glucosetools"
            openaps device remove cgm 2>/dev/null
            if [[ -z ${ttyport} ]]; then
                openaps device add cgm medtronic ${serial} || die "Can't add cgm"
            else
                openaps device add cgm mmeowlink subg_rfspy ${ttyport} ${serial} || die "Can't add cgm"
            fi
            for type in mdt-cgm; do
                printf '%s\n' "importing ${type} file"
                openaps import < ${SRC}/oref0/lib/oref0-setup/${type}.json || die "Could not import ${type}.json"
            done
        elif [[ ${CGM,,} =~ "G4" || ${CGM,,} =~ "shareble" ]]; then
            if [[ ${ENABLE} =~ "raw" ]]; then
                openaps report add raw-cgm/raw-entries.json JSON cgm oref0_glucose --hours "24" --threshold "100"
            fi
        fi

        # configure optional features
        if [[ ${ENABLE} =~ autosens && ${ENABLE} =~ meal ]]; then
            EXTRAS="settings/autosens.json monitor/meal.json"
        elif [[ ${ENABLE} =~ autosens ]]; then
            EXTRAS="settings/autosens.json"
        elif [[ ${ENABLE} =~ meal ]]; then
            EXTRAS='"" monitor/meal.json'
        fi

        printf '%s\n' "Running: openaps report add enact/suggested.json text determine-basal shell monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json $EXTRAS"
        openaps report add enact/suggested.json text determine-basal shell monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json ${EXTRAS}

        printf "\n"
        if [[ ${ttyport} =~ "spi" ]]; then
            printf '%s\n' "Resetting spi_serial"
            reset_spi_serial.py
        fi
        printf '%s\n' "Scanning for best frequency for pump communications:"
        openaps mmtune
        printf "\n"

        if [[ -z ${HEADLESS} ]]; then
            read -p "Schedule openaps in cron? [Y]/n " -r
        fi
        if ! [[ ${REPLY:-Y} =~ ^[Nn]$ ]] || ! [[ -z ${HEADLESS} ]]; then
            # add crontab entries
            (crontab -l; crontab -l | grep -q "${NIGHTSCOUT_HOST}" || printf '%s\n' "NIGHTSCOUT_HOST=${NIGHTSCOUT_HOST}") | crontab -
            (crontab -l; crontab -l | grep -q "API_SECRET=" || printf '%s\n' "API_SECRET=$(nightscout hash-api-secret ${API_SECRET})") | crontab -
            (crontab -l; crontab -l | grep -q "PATH=" || printf '%s\n' "PATH=${PATH}" ) | crontab -
            if [[ ${CGM,,} =~ "shareble" ]]; then
                # cross-platform hack to make sure experimental bluetoothd is running for openxshareble
                (crontab -l; crontab -l | grep -q "killall bluetoothd" || printf '%s\n' '@reboot sleep 30; sudo killall bluetoothd; sudo /usr/local/bin/bluetoothd --experimental; bluetooth_rfkill_event > /dev/null 2>&1') | crontab -
            fi
            (crontab -l; crontab -l | grep -q "sudo wpa_cli scan" || printf '%s\n' '* * * * * sudo wpa_cli scan') | crontab -
            (crontab -l; crontab -l | grep -q "killall -g --older-than" || printf '%s\n' '* * * * * killall -g --older-than 15m openaps') | crontab -
            (crontab -l; crontab -l | grep -q "cd ${directory} && oref0-reset-git" || printf '%s\n' "* * * * * cd ${directory} && oref0-reset-git") | crontab -
            if ! [[ ${CGM,,} =~ "mdt" ]]; then
                (crontab -l; crontab -l | grep -q "cd ${directory} && ps aux | grep -v grep | grep -q 'openaps get-bg'" || printf '%s\n' "* * * * * cd ${directory} && ps aux | grep -v grep | grep -q 'openaps get-bg' || ( date; openaps get-bg ; cat cgm/glucose.json | json -a sgv dateString | head -1 ) | tee -a /var/log/openaps/cgm-loop.log") | crontab -
            fi
            (crontab -l; crontab -l | grep -q "cd ${directory} && ps aux | grep -v grep | grep -q 'openaps ns-loop'" || printf '%s\n' "* * * * * cd ${directory} && ps aux | grep -v grep | grep -q 'openaps ns-loop' || openaps ns-loop | tee -a /var/log/openaps/ns-loop.log") | crontab -
            if [[ ${ENABLE} =~ autosens ]]; then
                (crontab -l; crontab -l | grep -q "cd ${directory} && ps aux | grep -v grep | grep -q 'openaps autosens'" || printf '%s\n' "* * * * * cd ${directory} && ps aux | grep -v grep | grep -q 'openaps autosens' || openaps autosens | tee -a /var/log/openaps/autosens-loop.log") | crontab -
            fi
            if [[ ${ttyport} =~ "spi" ]]; then
                (crontab -l; crontab -l | grep -q "cd ${directory} && reset_spi_serial.py" || printf '%s\n' "@reboot cd ${directory} && reset_spi_serial.py") | crontab -
            fi
            (crontab -l; crontab -l | grep -q "cd ${directory} && ( ps aux | grep -v grep | grep -q 'openaps pump-loop'" || printf '%s\n' "* * * * * cd ${directory} && ( ps aux | grep -v grep | grep -q 'openaps pump-loop' || openaps pump-loop ) 2>&1 | tee -a /var/log/openaps/pump-loop.log") | crontab -
            crontab -l

            if [[ ${CGM,,} =~ "shareble" ]]; then
                printf "\n"
                printf "To pair your G4 Share receiver, open its Setttings, select Share, Forget Device (if previously paired), then turn sharing On\n"
            fi
        fi
        # printf '%s\n%s\n' "[{\"OPENAPS_HOME\":\"${OPENAPS_HOME}\"" "\"SRC\":\"${SRC}\"}]" "\n\n\ntest" > ${manifest}
        printf "[{\"openaps\":\"${OPENAPS_HOME}\",\"src\":\"${SRC}\"}]" | json > ${manifest}
    fi
}


# defaults
max_iob=4
CGM="G4"
DIR=""
directory=""
EXTRAS=""
manifest="${HOME}/openaps_install.json"

for i in "$@"
do
case ${i} in
    -d=*|--dir=*)
    DIR="${i#*=}"
    # ~/ paths have to be expanded manually
    DIR="${DIR/#\~/${HOME}}"
    directory="$(readlink -m ${DIR})"
    shift # past argument=value
    ;;
    -s=*|--serial=*)
    serial="${i#*=}"
    shift # past argument=value
    ;;
    -t=*|--tty=*)
    ttyport="${i#*=}"
    shift # past argument=value
    ;;
    -m=*|--max_iob=*)
    max_iob="${i#*=}"
    shift # past argument=value
    ;;
    -c=*|--cgm=*)
    CGM="${i#*=}"
    shift # past argument=value
    ;;
    -n=*|--ns-host=*)
    NIGHTSCOUT_HOST="${i#*=}"
    shift # past argument=value
    ;;
    -a=*|--api-secret=*)
    API_SECRET="${i#*=}"
    shift # past argument=value
    ;;
    -e=*|--enable=*)
    ENABLE="${i#*=}"
    shift # past argument=value
    ;;
    -b=*|--bleserial=*)
    BLE_SERIAL="${i#*=}"
    shift # past argument=value
    ;;
    -o=*|--option=*)
    OPTION="${i#*=}"
    shift # past argument=value
    ;;
    -r=*|--repo=*)
    REPO="${i#*=}"
    shift # past argument=value
    ;;
    --h*|--headless*)
    HEADLESS="on"
    shift # past argument=value
    ;;
    *)
    # unknown option
    printf '%s\n' "Option '${i#*=}' unknown"
    ;;
esac
done

if [[ -z ${OPTION} ]]; then
    read -p "What are we doing? ([setup]|refresh|uninstall) " -r
    OPTION=${REPLY:-setup}
    if [[ -z ${OPTION} || ("${OPTION}" != "setup" && "${OPTION}" != "uninstall" && "${OPTION}" != "refresh") ]]; then OPTION="setup"; fi
fi
# Run the specified option's related function
printf "Running Option: ${OPTION^^}"
if ! [[ -z ${HEADLESS} ]];then
    printf " in HEADLESS mode\n"
else
    printf " \n"
fi
${OPTION}
