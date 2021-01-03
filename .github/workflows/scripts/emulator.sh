#!/usr/bin/env bash
export VEXE=./v
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk-bundle"
#echo yes | $ANDROID_SDK_ROOT/tools/bin/sdkmanager 'system-images;android-23;google_apis;x86_64'
#echo no | $ANDROID_SDK_ROOT/tools/bin/avdmanager create avd --force --name test --abi google_apis/x86_64 --package 'system-images;android-23;google_apis;x86_64'
#$ANDROID_SDK_ROOT/emulator/emulator -avd 'Nexus 5X'
# Debugging
ADB_TAGS="SOKOL:I SOKOL:W SOKOL:D"
#ADB_TAGS="$ADB_TAGS SOKOL:I SOKOL:W SOKOL:D"
adb logcat -c
adb logcat $ADB_TAGS *:E -v color &
vab/vab --nocache -v 3 --device auto --archs 'armeabi-v7a' examples/sokol/particles
