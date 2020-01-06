#!/sbin/sh
#
###########################################
#
# This file is part of the FlameGApps Project by ayandebnath @xda-developers
#
# The FlameGApps scripts are free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License,or
# (at your option) any later version, w/FlameGApps installable zip exception.
#
# These scripts are distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
###########################################
# File Name    : installer.sh
# Last Updated : 2020-01-06
###########################################
##
# List of the Basic edition gapps files
basic_gapps_list="
DigitalWellbeing
GoogleLocationHistory
SoundPickerGoogle"

# List of the Full edition gapps files
full_gapps_list="
DeviceHealthServices
DigitalWellbeing
GoogleClock
GoogleCalendar
GoogleCalculator
GoogleContacts
GoogleDialer
GoogleMessages
GoogleKeyboard
GooglePhotos
GoogleLocationHistory
MarkupGoogle
SoundPickerGoogle
WallpaperPickerGoogle"

ui_print() {
  echo "ui_print $1" > "$OUTFD";
  echo "ui_print" > "$OUTFD";
}

set_progress() { echo "set_progress $1" > "$OUTFD"; }

recovery_actions() {
  OLD_LD_LIB=$LD_LIBRARY_PATH
  OLD_LD_PRE=$LD_PRELOAD
  OLD_LD_CFG=$LD_CONFIG_FILE
  unset LD_LIBRARY_PATH
  unset LD_PRELOAD
  unset LD_CONFIG_FILE
}

recovery_cleanup() {
  [ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
  [ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
  [ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG
}

unmount_part() {
    ui_print "- Unmounting $mounts";
    for m in $mounts; do
    umount "$m"
    done
}

abort() {
    sleep 1;
    ui_print "Aborting...";
    sleep 3;
    unmount_part;
    take_failed_logs;
    recovery_cleanup;
    exit 1;
}

exit_all() {
    sleep 0.5;
    unmount_part;
    sleep 0.5;
    take_success_logs;
    set_progress 0.90;
    recovery_cleanup;
    sleep 0.5;
    ui_print "Installation Finished..!";
    ui_print " ";
    set_progress 1.00;
}

# Pre Mount Process
for p in "/system" "/system_root"; do
  if [ -d $p ]; then
    umount "$p"
  fi
done

# Mount Process
set_progress 0.10;
ui_print "Mounting Partitions";
sleep 1;
# Detect A/B partition layout https://source.android.com/devices/tech/ota/ab_updates
# and system-as-root https://source.android.com/devices/bootloader/system-as-root
block=/dev/block/bootdevice/by-name/system
device_abpartition=false
active_slot=`getprop ro.boot.slot_suffix`
if [ ! -z "$active_slot" ]; then
  device_abpartition=true
  MOUNT_POINT=/system
  block=/dev/block/bootdevice/by-name/system$active_slot
  ui_print "- Current boot slot: $active_slot";
elif [ -n "$(cat /etc/fstab | grep /system_root)" ];
then
  device_abpartition=false
  MOUNT_POINT=/system_root
else
  device_abpartition=false
  MOUNT_POINT=/system
fi

# Mount Partitions
mounts=""
for p in "/cache" "/data" "$MOUNT_POINT" "/vendor"; do
  if [ -d "$p" ] && grep -q "$p" "/etc/fstab" && ! mountpoint -q "$p"; then
    mounts="$mounts $p"
  fi
done
ui_print "- Mounting $mounts";
for m in $mounts; do
  mount "$m"
done

# Remount $MOUNT_POINT RW
ui_print "- Mounting  $MOUNT_POINT RW";
mount -o rw,remount "$block" $MOUNT_POINT || mount -o rw,remount $MOUNT_POINT

# Try to detect system-as-root through /system/init.rc like Magisk does
# Remount /system to /system_root if we have system-as-root and bind /system to /system_root/system (like Magisk does)
# For reference, check https://github.com/topjohnwu/Magisk/blob/master/scripts/util_functions.sh
sleep 0.3;
if [ -f /system/init.rc ]; then
  ui_print "- System is /system/system";
  ui_print "- Device is system-as-root";
  [ -L /system_root ] && rm -f /system_root
  mkdir /system_root
  mount --move /system /system_root
  mount -o bind /system_root/system /system
  SYSTEM=/system_root/system
  mounts="$mounts /system_root"
elif [ -f /system_root/init.rc ]; then
  ui_print "- System is /system_root/system";
  ui_print "- Device is system-as-root";
  SYSTEM=system_root/system
else
  ui_print "- System is /system";
  SYSTEM=/system
fi

ui_print " ";

TMP="/tmp"

recovery_actions;

PROPFILES="$SYSTEM/build.prop $TMP/flame.prop"

get_file_prop() {
  grep -m1 "^$2=" "$1" | cut -d= -f2
}

get_prop() {
  #check known .prop files using get_file_prop
  for f in $PROPFILES; do
    if [ -e "$f" ]; then
      prop="$(get_file_prop "$f" "$1")"
      if [ -n "$prop" ]; then
        break #if an entry has been found, break out of the loop
      fi
    fi
  done
  #if prop is still empty; try to use recovery's built-in getprop method; otherwise output current result
  if [ -z "$prop" ]; then
    getprop "$1" | cut -c1-
  else
    printf "$prop"
  fi
}

# Prepare Logs
log_folder="$(dirname "$ZIPFILE")";
mkdir $TMP/flamegapps
chmod 0755 $TMP/flamegapps
mkdir $TMP/flamegapps/logs
chmod 0755 $TMP/flamegapps/logs
log_dir="$TMP/flamegapps/logs"
flame_log="$log_dir/installation_log.txt"
flame_prop="$TMP/flame.prop"
build_prop="$SYSTEM/build.prop"
details_log="$log_dir/details.prop"

take_failed_logs() {
    ui_print "- Copying logs to $log_folder";
    ui_print " ";
    cp -f $TMP/recovery.log $log_dir/recovery.log
    cd $log_dir
    tar -cz -f "$TMP/flamegapps_debug_failed_logs.tar.gz" *
    cp -f $TMP/flamegapps_debug_failed_logs.tar.gz $log_folder/flamegapps_debug_failed_logs.tar.gz
    cd /
    rm -rf $log_dir;
}

take_success_logs() {
    ui_print "- Copying logs to $log_folder";
    ui_print " ";
    cp -f $TMP/recovery.log $log_dir/recovery.log
    cd $log_dir
    tar -cz -f "$TMP/flamegapps_debug_success_logs.tar.gz" *
    cp -f $TMP/flamegapps_debug_success_logs.tar.gz $log_folder/flamegapps_debug_success_logs.tar.gz
    cd /
    rm -rf $log_dir;
}

echo ---------------------------------------------------- >> $flame_log;
echo "---------- FlameGApps Installation Logs ----------" >> $flame_log;
echo "# " >> $flame_log;
echo "- Mount Point: $MOUNT_POINT" >> $flame_log;
echo "- Current slot is: $active_slot" >> $flame_log;
echo ---------------------------------------------------- >> $flame_log;

# Get ROM & Device Information
flame_android="$(get_prop "ro.flame.android")"
flame_sdk="$(get_prop "ro.flame.sdk")"
flame_arch="$(get_prop "ro.flame.arch")"
edition_type="$(get_prop "ro.flame.edition")"
rom_version="$(get_prop "ro.build.version.release")"
rom_sdk="$(get_prop "ro.build.version.sdk")"
device_architecture="$(get_prop "ro.product.cpu.abilist")"
device_code="$(get_prop "ro.product.device")"

echo ---------------------------------------------------- >> $flame_log;
echo "# Device And Flame Information" >> $flame_log;
echo "- Flame version is: $flame_android" >> $flame_log;
echo "- Flame SDK is: $flame_sdk" >> $flame_log;
echo "- Flame ARCH is: $flame_arch" >> $flame_log;
echo "- ROM version is: $rom_version" >> $flame_log;
echo "- ROM SDK is: $rom_sdk" >> $flame_log;
echo "- Device ARCH is: $device_architecture" >> $flame_log;
echo "- Device is: $device_code" >> $flame_log;
echo "# End Device And Flame Information" >> $flame_log;
echo ---------------------------------------------------- >> $flame_log;

# Get Prop Details Before Compatibility Checks
cat $build_prop >> $details_log;
cat $flame_prop >> $details_log;

# Prepare Msgs
wrong_version="! Wrong Android Version Detected"
wrong_arch="! Wrong Device Architecture Detected"
pkg_details="! This Package is For Android: $flame_android Only"
rom_ver_info="Your ROM is Android: $rom_version.0"
pkg_details_arch="This Package is For Device: $flame_arch Only"
edition_detection_failed="! Failed to detect FlameGApps Edition type"

set_progress 0.20;
sleep 0.5;
ui_print "Getting Device And ROM Information";
sleep 1;
ui_print "- Android Version : $rom_version Detected";
sleep 0.5;
ui_print "- Android SDK     : $rom_sdk Detected";
sleep 0.5;

if [ ! "$rom_sdk" = "$flame_sdk" ]; then
  ui_print " ";
  ui_print "****************** WARNING ******************";
  ui_print " ";
  ui_print "$wrong_version ";
  sleep 0.5;
  ui_print "$pkg_details ";
  sleep 0.5;
  ui_print "$rom_ver_info ";
  sleep 0.5;
  ui_print " ";
  ui_print "******* FlameGApps Installation Failed *******";
  ui_print " ";
  abort;
fi

if [ -z "$device_architecture" ]; then
  device_architecture="$(get_prop "ro.product.cpu.abi")"
fi

case "$device_architecture" in
  *x86_64*) arch="x86_64"; libfolder="lib64";;
  *x86*) arch="x86"; libfolder="lib";;
  *arm64*) arch="arm64"; libfolder="lib64";;
  *armeabi*) arch="arm"; libfolder="lib";;
  *) arch="unknown";;
esac

ui_print "- Device Arch     : $arch Detected";
sleep 1;

if [ ! "$arch" = "$flame_arch" ]; then
  ui_print " ";
  ui_print "****************** WARNING ******************";
  ui_print " ";
  ui_print "$wrong_arch ";
  sleep 0.5;
  ui_print "$pkg_details_arch ";
  sleep 0.5;
  ui_print "Your Device is: $arch ";
  sleep 0.5;
  ui_print " ";
  ui_print "******* FlameGApps Installation Failed *******";
  ui_print " ";
  abort;
fi

echo "# " >> $flame_log;
echo "- Compatibility checks completed" >> $flame_log;
echo "# " >> $flame_log;
echo ---------------------------------------------------- >> $flame_log;
echo "*** Starting Installation ***" >> $flame_log;
echo ---------------------------------------------------- >> $flame_log;

# Creat UNZIP Directory
set_progress 0.25;
ui_print " ";
ui_print "Creating unzip directory in tmp";
sleep 1.5;
mkdir $TMP/release
chmod 0755 $TMP/release

# Pre-installed unnecessary app list
# Basic list for Basic Edition
BASIC_LIST="
$SYSTEM/app/ExtShared
$SYSTEM/app/FaceLock
$SYSTEM/app/GoogleExtShared
$SYSTEM/app/GoogleContactSyncAdapter
$SYSTEM/priv-app/ExtServices
$SYSTEM/priv-app/Provision
$SYSTEM/priv-app/provision
$SYSTEM/priv-app/AndroidPlatformServices
$SYSTEM/priv-app/GoogleServicesFramework
$SYSTEM/priv-app/GmsCoreSetupPrebuilt
$SYSTEM/priv-app/GmsCore
$SYSTEM/priv-app/PrebuiltGmsCore
$SYSTEM/priv-app/PrebuiltGmsCorePi
$SYSTEM/priv-app/Phonesky
$SYSTEM/priv-app/SetupWizard
$SYSTEM/priv-app/LineageSetupWizard
$SYSTEM/priv-app/PixelSetupWizard
$SYSTEM/priv-app/Wellbeing
$SYSTEM/priv-app/wellbeing
$SYSTEM/priv-app/WellbeingGooglePrebuilt
$SYSTEM/priv-app/WellbeingPrebuilt"

# Full list for Full Edition
FULL_LIST="
$SYSTEM/app/ExtShared
$SYSTEM/app/FaceLock
$SYSTEM/app/Clock
$SYSTEM/app/DeskClock
$SYSTEM/app/DashClock
$SYSTEM/app/PrebuiltDeskClock
$SYSTEM/app/Calculator
$SYSTEM/app/Calculator2
$SYSTEM/app/ExactCalculator
$SYSTEM/app/Calendar
$SYSTEM/app/CalendarPrebuilt
$SYSTEM/app/Eleven
$SYSTEM/app/message
$SYSTEM/app/messages
$SYSTEM/app/Messages
$SYSTEM/app/Markup
$SYSTEM/app/MarkupGoogle
$SYSTEM/app/PrebuiltBugle
$SYSTEM/app/Hangouts
$SYSTEM/app/SoundPicker
$SYSTEM/app/PrebuiltSoundPicker
$SYSTEM/app/SoundPickerPrebuilt
$SYSTEM/app/Contact
$SYSTEM/app/Contacts
$SYSTEM/app/Photos
$SYSTEM/app/PhotosPrebuilt
$SYSTEM/app/CalculatorGooglePrebuilt
$SYSTEM/app/CalendarGooglePrebuilt
$SYSTEM/app/Messaging
$SYSTEM/app/Messenger
$SYSTEM/app/messaging
$SYSTEM/app/Email
$SYSTEM/app/Email2
$SYSTEM/app/Gmail
$SYSTEM/app/LatinIMEGooglePrebuilt
$SYSTEM/app/Browser
$SYSTEM/app/Browser2
$SYSTEM/app/Jelly
$SYSTEM/app/Via
$SYSTEM/app/LatinIME
$SYSTEM/app/LatinIMEPrebuilt
$SYSTEM/priv-app/ExtServices
$SYSTEM/priv-app/Browser
$SYSTEM/priv-app/Browser2
$SYSTEM/priv-app/Jelly
$SYSTEM/priv-app/Via
$SYSTEM/priv-app/LatinIME
$SYSTEM/priv-app/GoogleServicesFramework
$SYSTEM/priv-app/Provision
$SYSTEM/priv-app/provision
$SYSTEM/priv-app/PrebuiltGmsCore
$SYSTEM/priv-app/PrebuiltGmsCorePi
$SYSTEM/priv-app/GmsCore
$SYSTEM/priv-app/PrebuiltSetupWizard
$SYSTEM/priv-app/SetupWizard
$SYSTEM/priv-app/SetupWizardPrebuilt
$SYSTEM/priv-app/PixelSetupWizard
$SYSTEM/priv-app/LineageSetupWizard
$SYSTEM/priv-app/Wellbeing
$SYSTEM/priv-app/CarrierSetup
$SYSTEM/priv-app/ConfigUpdater
$SYSTEM/priv-app/GmsCoreSetupPrebuilt
$SYSTEM/priv-app/Gallery
$SYSTEM/priv-app/Gallery2
$SYSTEM/priv-app/Camera2
$SYSTEM/priv-app/Photos
$SYSTEM/priv-app/Contact
$SYSTEM/priv-app/Contacts
$SYSTEM/priv-app/Dialer
$SYSTEM/priv-app/GoogleContacts
$SYSTEM/priv-app/GoogleDialer
$SYSTEM/priv-app/Music
$SYSTEM/priv-app/Music2
$SYSTEM/priv-app/SnapGallery
$SYSTEM/priv-app/Clock
$SYSTEM/priv-app/Calendar
$SYSTEM/priv-app/Calculator
$SYSTEM/priv-app/Hangouts
$SYSTEM/priv-app/Messaging
$SYSTEM/priv-app/Gmail
$SYSTEM/priv-app/Email
$SYSTEM/priv-app/Email2
$SYSTEM/priv-app/Eleven
$SYSTEM/priv-app/Maps
$SYSTEM/priv-app/GoogleMaps
$SYSTEM/priv-app/SounPicker
$SYSTEM/priv-app/GoogleMapsPrebuilt
$SYSTEM/priv-app/MarkupGoogle
$SYSTEM/priv-app/PrebuiltDeskClock
$SYSTEM/priv-app/SoundPickerPrebuilt
$SYSTEM/priv-app/PrebuiltSoundPicker
$SYSTEM/priv-app/Turbo
$SYSTEM/priv-app/Wallpaper
$SYSTEM/priv-app/Wallpapers
$SYSTEM/priv-app/WallpaperPrebuilt
$SYSTEM/priv-app/WallpapersPrebuilt
$SYSTEM/priv-app/WallpapersGooglePrebuilt
$SYSTEM/priv-app/WallpaperGooglePrebuilt
$SYSTEM/priv-app/DeviceHealthService
$SYSTEM/priv-app/AndroidPlafoPlatformServices
$SYSTEM/priv-app/LatinIMEGooglePrebuilt"

# Basic Product List for Android Q
BASIC_LIST_PRODUCT="
$SYSTEM/product/app/ExtShared
$SYSTEM/product/app/FaceLock
$SYSTEM/product/priv-app/ExtServices
$SYSTEM/product/priv-app/GoogleExtServicesPrebuilt
$SYSTEM/product/priv-app/GoogleServicesFramework
$SYSTEM/product/priv-app/Provision
$SYSTEM/product/priv-app/provision
$SYSTEM/product/priv-app/CarrierSetup
$SYSTEM/product/priv-app/ConfigUpdater
$SYSTEM/product/priv-app/GmsCoreSetupPrebuilt
$SYSTEM/product/priv-app/PrebuiltGmsCore
$SYSTEM/product/priv-app/PrebuiltGmsCoreQt
$SYSTEM/product/priv-app/GmsCore
$SYSTEM/product/priv-app/Phonesky
$SYSTEM/product/priv-app/SetupWizardPrebuilt
$SYSTEM/product/priv-app/SetupWizard
$SYSTEM/product/priv-app/PixelSetupWizard
$SYSTEM/product/priv-app/PixelSetup
$SYSTEM/product/priv-app/WellbeingPrebuilt"

# Full Product list for Android Q
FULL_LIST_PRODUCT="
$SYSTEM/product/app/ExtShared
$SYSTEM/product/app/Clock
$SYSTEM/product/app/DeskClock
$SYSTEM/product/app/DashClock
$SYSTEM/product/app/Calculator
$SYSTEM/product/app/Calculator2
$SYSTEM/product/app/ExactCalculator
$SYSTEM/product/app/Calendar
$SYSTEM/product/app/message
$SYSTEM/product/app/messages
$SYSTEM/product/app/Maps
$SYSTEM/product/app/Contacts
$SYSTEM/product/app/Photos
$SYSTEM/product/app/Gallery2
$SYSTEM/product/app/Messaging
$SYSTEM/product/app/messaging
$SYSTEM/product/app/Email
$SYSTEM/product/app/Email2
$SYSTEM/product/app/Browser
$SYSTEM/product/app/Browser2
$SYSTEM/product/app/Jelly
$SYSTEM/product/app/Gallery3d
$SYSTEM/product/app/GalleryGo
$SYSTEM/product/app/GalleryGoPrebuilt
$SYSTEM/product/app/LatinIME
$SYSTEM/product/priv-app/LatinIME
$SYSTEM/product/priv-app/ExtServices
$SYSTEM/product/priv-app/GoogleServicesFramework
$SYSTEM/product/priv-app/Provision
$SYSTEM/product/priv-app/provision
$SYSTEM/product/priv-app/PrebuiltGmsCore
$SYSTEM/product/priv-app/PrebuiltGmsCorePi
$SYSTEM/product/priv-app/PrebuiltGmsCoreQt
$SYSTEM/product/priv-app/GmsCore
$SYSTEM/product/priv-app/SetupWizard
$SYSTEM/product/priv-app/LineageSetupWizard
$SYSTEM/product/priv-app/Gallery
$SYSTEM/product/priv-app/Gallery2
$SYSTEM/product/priv-app/Photos
$SYSTEM/product/priv-app/GalleryGo
$SYSTEM/product/priv-app/GalleryGoPrebuilt
$SYSTEM/product/priv-app/Contact
$SYSTEM/product/priv-app/Contacts
$SYSTEM/product/priv-app/Dialer
$SYSTEM/product/priv-app/GoogleContacts
$SYSTEM/product/priv-app/GoogleDialer
$SYSTEM/product/priv-app/Music2
$SYSTEM/product/priv-app/crDroidMusic
$SYSTEM/product/priv-app/Browser
$SYSTEM/product/priv-app/Browser2
$SYSTEM/product/priv-app/Jelly
$SYSTEM/product/priv-app/Eleven
$SYSTEM/product/priv-app/Gallery3d
$SYSTEM/product/priv-app/Gmail
$SYSTEM/product/priv-app/Email
$SYSTEM/product/priv-app/Email2
$SYSTEM/product/priv-app/Turbo
$SYSTEM/product/priv-app/WallpaperPickerGooglePrebuilt
$SYSTEM/product/priv-app/WellbeingPrebuilt"

# Remove Pre-Installed Unnecessary System Apps
ui_print " ";
if [ "$edition_type" = "basic" ]; then
  ui_print "Removing unnecessary system apps";
  set_progress 0.30;
  sleep 1.5;
  echo "- Removing Basic list files" >> $flame_log;
  rm -rf $BASIC_LIST; #Remove basic list files if basic edition detected
   if [ "$flame_sdk" = "29" ]; then
     echo "- Removing Basic Product list files too" >> $flame_log;
     rm -rf $BASIC_LIST_PRODUCT; #Remove basic list product files if android 10 detected
   fi
elif [ "$edition_type" = "full" ]; then
  ui_print "Removing unnecessary system apps";
  set_progress 0.30;
  sleep 1.5;
  echo "- Removing Full list files" >> $flame_log;
  rm -rf $FULL_LIST; #Remove full list files if full edition detected
   if [ "$flame_sdk" = "29" ]; then
     echo "- Removing Full Product list files too" >> $flame_log;
     rm -rf $FULL_LIST_PRODUCT; #Remove full list product files if android 10 detected
   fi
else
  #Abort the installation if the installer failed to detect edition type
  ui_print "****************** WARNING *******************";
ui_print " ";
  sleep 0.5;
  echo "- Failed to detect edition type" >> $flame_log;
  ui_print "$edition_detection_failed";
  sleep 0.5;
  ui_print " ";
  ui_print "******* FlameGApps Installation Failed *******";
  abort;
fi

# Start Installation
CORE_DIR="$TMP/tar_core"
GAPPS_DIR="$TMP/tar_gapps"
UNZIP_FOLDER="$TMP/release"
EX_SYSTEM="$UNZIP_FOLDER/system"

# Ensure gapps_list
if [ "$edition_type" = "basic" ]; then
  gapps_list="$basic_gapps_list"
elif [ "$edition_type" = "full" ]; then
  gapps_list="$full_gapps_list"
fi

unzip_core() {
    set_progress 0.40;
    ui_print " ";
    ui_print "Copying core files to unzip directory";
    ui_print " ";
    unzip -o "$ZIPFILE" 'tar_core/*' -d $TMP;
}

unzip_gapps() {
    set_progress 0.60;
    ui_print " ";
    ui_print "Copying gapps files to unzip directory";
    ui_print " ";
    unzip -o "$ZIPFILE" 'tar_gapps/*' -d $TMP;
}

install_core() {
    set_progress 0.50;
    ui_print "- Installing Core GApps";
    tar -xf "$CORE_DIR/Core.tar.xz" -C $UNZIP_FOLDER;
    file_list="$(find "$EX_SYSTEM/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$EX_SYSTEM/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
     install -D "$EX_SYSTEM/${file}" "$SYSTEM/${file}"
     chmod 0644 "$SYSTEM/${file}";
    done
    for dir in $dir_list; do
     chmod 0755 "$SYSTEM/${dir}";
    done
    rm -rf $CORE_DIR
    rm -rf $UNZIP_FOLDER/system
}

install_gapps() {
    for g in $gapps_list; do
    ui_print "- Installing $g";
    tar -xf "$GAPPS_DIR/$g.tar.xz" -C $UNZIP_FOLDER;
    rm -rf $GAPPS_DIR/$g.tar.xz
    done
    file_list="$(find "$EX_SYSTEM/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$EX_SYSTEM/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
     install -D "$EX_SYSTEM/${file}" "$SYSTEM/${file}"
     chmod 0644 "$SYSTEM/${file}";
    done
    for dir in $dir_list; do
     chmod 0755 "$SYSTEM/${dir}";
    done
    rm -rf $UNZIP_FOLDER/system
}

# Unzip & Install Core GApps Files
echo "# " >> $flame_log;
echo "- Unzipping Core GApps Files" >> $flame_log;
unzip_core >> $flame_log;
echo "# " >> $flame_log;
echo "- Installing Core GApps Files" >> $flame_log;
install_core >> $flame_log;
echo "# " >> $flame_log;

# Unzip & Install GApps Files
echo "# " >> $flame_log;
echo "- Unzipping GApps Files" >> $flame_log;
unzip_gapps >> $flame_log;
echo "# " >> $flame_log;

# Install GApps List Files
echo "- Installing GApps Files" >> $flame_log;
echo "# " >> $flame_log;
install_gapps >> $flame_log;
# End

echo ---------------------------------------------------- >> $flame_log;
echo "*** Installation Finished ***" >> $flame_log;
echo ---------------------------------------------------- >> $flame_log;

set_progress 0.80;
ui_print " ";
ui_print "Performing misc tasks";
# Install addon.d script
if [ -d "$SYSTEM/addon.d" ]; then
  rm -rf $SYSTEM/addon.d/69_flame.sh
  cp -f $TMP/addon.d.sh $SYSTEM/addon.d/69_flame.sh
  chmod 0755 $SYSTEM/addon.d/69_flame.sh
fi

# Set Google Dialer as Default Phone App if Available
if [ -e $SYSTEM/priv-app/GoogleDialer/GoogleDialer.apk ]; then
  # set Google Dialer as default; based on the work of osm0sis @ xda-developers
  setver="122"  # lowest version in MM, tagged at 6.0.0
  setsec="/data/system/users/0/settings_secure.xml"
  if [ -f "$setsec" ]; then
    if grep -q 'dialer_default_application' "$setsec"; then
      if ! grep -q 'dialer_default_application" value="com.google.android.dialer' "$setsec"; then
        curentry="$(grep -o 'dialer_default_application" value=.*$' "$setsec")"
        newentry='dialer_default_application" value="com.google.android.dialer" package="android" />\r'
        sed -i "s;${curentry};${newentry};" "$setsec"
      fi
    else
      max="0"
      for i in $(grep -o 'id=.*$' "$setsec" | cut -d '"' -f 2); do
        test "$i" -gt "$max" && max="$i"
      done
      entry='<setting id="'"$((max + 1))"'" name="dialer_default_application" value="com.google.android.dialer" package="android" />\r'
      sed -i "/<settings version=\"/a\ \ ${entry}" "$setsec"
    fi
  else
    if [ ! -d "/data/system/users/0" ]; then
      install -d "/data/system/users/0"
      chown -R 1000:1000 "/data/system"
      chmod -R 775 "/data/system"
      chmod 700 "/data/system/users/0"
    fi
    { echo -e "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>\r";
    echo -e '<settings version="'$setver'">\r';
    echo -e '  <setting id="1" name="dialer_default_application" value="com.google.android.dialer" package="android" />\r';
    echo -e '</settings>'; } > "$setsec"
  fi
  chown 1000:1000 "$setsec"
  chmod 600 "$setsec"
fi

exit_all;

# Installation Compleated
