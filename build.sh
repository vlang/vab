#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z ${ANDROID_SDK_ROOT+x} ]; then
	# ANDROID_HOME=${HOME}/Environments/Android/android-sdk-linux
	ANDROID_SDK_ROOT=${HOME}/Environments/Android/android-sdk-linux
fi
echo "Using default SDK $ANDROID_SDK_ROOT"

if [ -z ${ANDROID_NDK_ROOT+x} ]; then
	ANDROID_NDK_ROOT=${HOME}/Environments/Android/android-ndk-current
fi
echo "Using default NDK $ANDROID_NDK_ROOT"

if [ -z ${JAVA_HOME+x} ]; then
	# JAVA_HOME=/usr/lib/jvm/default-java # <- default location
	JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
	#JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
fi
echo "Using default Java $JAVA_HOME"

if [ -z ${V_HOME+x} ]; then
	V_HOME=${HOME}/Projects/v
fi
echo "Using V in ${V_HOME}"

#BUILD_TOOLS_VERSION="27.0.3"
BUILD_TOOLS_VERSION="29.0.3"
BUILD_TOOLS=${ANDROID_SDK_ROOT}/build-tools

PLATFORM_TOOLS=${ANDROID_SDK_ROOT}/platform-tools


APPNAME=vtest
APKFILE=${APPNAME}.apk
PACKAGENAME=org.v.${APPNAME}

#We've tested it with android version 22, 24, 28 and 29.
#You can target something like Android 28, but if you set ANDROIDVERSION to say 22, then
#Your app should (though not necessarily) support all the way back to Android 22.
ANDROIDVERSION=21
ANDROIDTARGET=${ANDROIDVERSION}

#Default is to be strip down, but your app can override it.
CFLAGS="-ffunction-sections -Os -fdata-sections -Wall -fvisibility=hidden"
LDFLAGS="-Wl,--hash-style=both,--gc-sections -s"
ANDROID_FULLSCREEN=y
UNAME=$(uname)

if [ $UNAME == Linux ]; then
	OS_NAME=linux-x86_64
fi

if [ $UNAME == Darwin ]; then
	OS_NAME=darwin-x86_64
fi

if [ "$OS" == "Windows_NT" ]; then
	OS_NAME=windows-x86_64
fi

VSRC="$1"
VOUT="$SCRIPT_DIR/v_android.c"

SRC=$VOUT
ANDROIDSRCS=${SRC}

echo "[V]"
echo -e "\tInput: $VSRC"
echo -e "\tOutput: $VOUT"

echo "[App]"
echo -e "\tName: $APPNAME"

echo "[Android]"
echo -e "\tSDK: $ANDROID_SDK_ROOT"
echo -e "\tNDK: $ANDROID_NDK_ROOT"
echo -e "\tBuild Tools: $BUILD_TOOLS/$BUILD_TOOLS_VERSION"
echo -e "\tPlatform Tools: $PLATFORM_TOOLS"

echo ""

# Compile V -> C
echo "Compiling V to C (sokol_main)"
${V_HOME}/v --enable-globals -os android -apk -o "$VOUT" "$VSRC"

#CFLAGS="${CFLAGS} -I./src"

CFLAGS="${CFLAGS} -ferror-limit=1 -Wall -Wextra -Wno-unused-variable -Wno-unused-parameter -Wno-unused-result -Wno-unused-function -Wno-missing-braces -Wno-unused-label -Werror=implicit-function-declaration"

# TMP Shut up
CFLAGS="${CFLAGS} -Wno-braced-scalar-init -Wno-incompatible-pointer-types -Wno-implicitly-unsigned-literal -Wno-pointer-sign -Wno-enum-conversion -Wno-int-conversion -Wno-int-to-pointer-cast -Wno-sign-compare -Wno-return-type"

CFLAGS="${CFLAGS} -Os -DANDROID -D__ANDROID__ -DAPPNAME=\"${APPNAME}\""

# TODO if full_screen
CFLAGS="${CFLAGS} -DANDROID_FULLSCREEN"

CFLAGS="${CFLAGS} -I${ANDROID_NDK_ROOT}/sysroot/usr/include -I${ANDROID_NDK_ROOT}/sysroot/usr/include/android -fPIC -DANDROIDVERSION=${ANDROIDVERSION}"

LDFLAGS="${LDFLAGS} -llog -landroid -lEGL -lGLESv2 -lm" #-lGLESv1_CM -lOpenSLES
#LDFLAGS="${LDFLAGS} -static"
LDFLAGS="${LDFLAGS} -shared" # -uANativeActivity_onCreate handled by SOKOL

CC_ARM64="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/bin/aarch64-linux-android${ANDROIDVERSION}-clang"
CC_ARM32="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/bin/armv7a-linux-androideabi${ANDROIDVERSION}-clang"
CC_x86="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/bin/x86_64-linux-android${ANDROIDVERSION}-clang"
CC_x86_64="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/bin/x86_64-linux-android${ANDROIDVERSION}-clang"

ADB="${PLATFORM_TOOLS}/adb"
AAPT="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/aapt"
ZIPALIGN="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/zipalign"
APKSIGNER="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/apksigner"
KEYTOOL="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/keytool"
DX="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/dx"


# Sokol
CFLAGS="${CFLAGS} -DSOKOL_DEBUG -DSOKOL_GLES2"
LDFLAGS="${LDFLAGS} -uANativeActivity_onCreate -usokol_main"

CFLAGS="${CFLAGS} -I "${V_HOME}/thirdparty/sokol" -I "${V_HOME}/thirdparty/sokol/util" " # -lpthread -ldl"

CFLAGS="${CFLAGS} -I ${V_HOME}/thirdparty/fontstash"
CFLAGS="${CFLAGS} -I $SCRIPT_DIR/freetype2-android/include" # -lfreetype"

#CFLAGS=${CFLAGS} -I "/usr/include/freetype2" -lfreetype -I "${V_HOME}/thirdparty/fontstash" -I "${V_HOME}/examples/sokol/particles"

CFLAGS_ARM64="-m64"
CFLAGS_ARM32="-mfloat-abi=softfp -m32"
CFLAGS_x86="-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32"
CFLAGS_x86_64="-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel"

TMP="/tmp"
VAPK="${TMP}/vapk"

rm -fr ${VAPK}

mkdir -p "${VAPK}/lib/arm64-v8a"
mkdir -p "${VAPK}/lib/armeabi-v7a"
mkdir -p "${VAPK}/lib/x86"
mkdir -p "${VAPK}/lib/x86_64"



# Cross compile .so lib files
# Can be uncommented during debug e.g. use only ARM32

#echo "Effective call (arm64-v8a)"
#echo "cc ${CFLAGS} ${CFLAGS_ARM64} -o ${VAPK}/lib/arm64-v8a/lib${APPNAME}.so ${ANDROIDSRCS} -L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/sysroot/usr/lib/aarch64-linux-android/${ANDROIDVERSION} ${LDFLAGS}"

echo "Building arm64-v8a"
${CC_ARM64} ${CFLAGS} ${CFLAGS_ARM64} -o ${VAPK}/lib/arm64-v8a/lib${APPNAME}.so ${ANDROIDSRCS} -L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/sysroot/usr/lib/aarch64-linux-android/${ANDROIDVERSION} ${LDFLAGS}

echo "Building armeabi-v7a"
${CC_ARM32} ${CFLAGS} ${CFLAGS_ARM32} -o ${VAPK}/lib/armeabi-v7a/lib${APPNAME}.so ${ANDROIDSRCS} -L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/sysroot/usr/lib/arm-linux-androideabi/${ANDROIDVERSION} ${LDFLAGS}

mkdir -p ${VAPK}/lib/armeabi
cp ${VAPK}/lib/armeabi-v7a/lib${APPNAME}.so ${VAPK}/lib/armeabi/

echo "Building x86"
${CC_x86} ${CFLAGS} ${CFLAGS_x86} -o ${VAPK}/lib/x86/lib${APPNAME}.so ${ANDROIDSRCS} -L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/sysroot/usr/lib/i686-linux-android/${ANDROIDVERSION} ${LDFLAGS}

echo "Building x86_64"
${CC_x86_64} ${CFLAGS} ${CFLAGS_x86_64} -o ${VAPK}/lib/x86_64/lib${APPNAME}.so  ${ANDROIDSRCS} -L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${OS_NAME}/sysroot/usr/lib/x86_64-linux-android/${ANDROIDVERSION} ${LDFLAGS}


# Build APK
VAPK_OUT=${VAPK}/..

cp -r $SCRIPT_DIR/android/* ${VAPK}/

mkdir -p ${VAPK}/assets
echo "V test asset file" > ${VAPK}/assets/asset.txt

rm -rf ${VAPK_OUT}/temp.apk
rm -rf ${VAPK_OUT}/vapk.unsigned.apk
rm -rf ${VAPK_OUT}/vapk.apk

rm -rf ${VAPK_OUT}/vapkrp

${AAPT} package -v -f -m \
	-S ${VAPK}/res \
	-J ${VAPK}/src \
	-M ${VAPK}/AndroidManifest.xml \
	-I ${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar \
	-A ${VAPK}/assets

#--target-sdk-version ${ANDROIDTARGET}

_BACK="$(pwd)"
cd "${VAPK}"

#RT_JAR="$JAVA_HOME/jre/lib/rt.jar"
RT_JAR=${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar

mkdir -p ${VAPK}/obj
mkdir -p ${VAPK}/bin

javac -d ./obj \
	-source 1.7 \
	-target 1.7 \
	-sourcepath src \
	-bootclasspath "$RT_JAR" \
	${VAPK}/src/org/v/vtest/R.java \
	${VAPK}/src/org/v/vtest/Native.java

${DX} --verbose --dex --output=bin/classes.dex ./obj

${AAPT} package -v -f \
	-S res \
	-M AndroidManifest.xml \
	-A assets \
	-I ${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar \
	-F ${VAPK_OUT}/temp.apk \
	bin


cd "$_BACK"


_BACK="$(pwd)"
cd "${VAPK}"

test -e lib/arm64-v8a/lib${APPNAME}.so   && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/arm64-v8a/lib${APPNAME}.so
test -e lib/armeabi/lib${APPNAME}.so     && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/armeabi/lib${APPNAME}.so
test -e lib/armeabi-v7a/lib${APPNAME}.so && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/armeabi-v7a/lib${APPNAME}.so
test -e lib/x86/lib${APPNAME}.so         && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/x86/lib${APPNAME}.so
test -e lib/x86_64/lib${APPNAME}.so      && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/x86_64/lib${APPNAME}.so
cd "$_BACK"

# -p ?
${ZIPALIGN} -v -f 4 ${VAPK_OUT}/temp.apk ${VAPK_OUT}/vapk.unsigned.apk


KEYSTORE_FILE="$SCRIPT_DIR/debug.keystore"
KEYSTORE_PASSWORD="android"

test -e $KEYSTORE_FILE || keytool -genkeypair -keystore $KEYSTORE_FILE -storepass android -alias androiddebugkey -keypass $KEYSTORE_PASSWORD -keyalg RSA -validity 10000 -dname 'CN=,OU=,O=,L=,S=,C='

${APKSIGNER} sign --ks "$KEYSTORE_FILE" --ks-pass pass:$KEYSTORE_PASSWORD --key-pass pass:$KEYSTORE_PASSWORD --ks-key-alias "androiddebugkey" --out ${VAPK_OUT}/vapk.apk ${VAPK_OUT}/vapk.unsigned.apk

#${APKSIGNER} sign --ks "$KEYSTORE_FILE" --ks-pass stdin --key-pass stdin --out ${VAPK_OUT}/vapk.apk ${VAPK_OUT}/vapk.unsigned.apk

${APKSIGNER} verify -v ${VAPK_OUT}/vapk.apk

# Install
if [ -z ${ANDROID_SERIAL+x} ]; then
	#ANDROID_SERIAL=emulator-5554
	#ANDROID_SERIAL=4df144551637af2d # S3
	ANDROID_SERIAL=a4599aaf # S5
	#ANDROID_SERIAL=R58M61681DP # A40
fi

echo "Deploying to device $ANDROID_SERIAL"
echo "adb -s \"$ANDROID_SERIAL\" install -r ${VAPK_OUT}/vapk.apk"
${ADB} -s "$ANDROID_SERIAL" install -r ${VAPK_OUT}/vapk.apk


# Other handy adb (linux) commands (if you have platform-tools in your PATH):

# List devices:
# adb devices -l

# Logcat from cmdline:
# ANDROID_SERIAL=<device id> adb logcat

# Logcat clear
# ANDROID_SERIAL=<device id> adb logcat -c

# ANDROID_SERIAL=<device id> adb logcat -d > logcat.txt

# ADB shell:
# ANDROID_SERIAL=<device id> adb shell

# Kill ADB - as it can mess with your USB on some Linux distros, if kept running for too long *sigh*
killall adb