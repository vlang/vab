# Install
Dependencies: V, Linux, Java 8, Android SDK + NDK
```
git clone git@github.com:Larpon/vab.git
cd vab
v vab.v
```

If vab fails to detect your environment you can set ENV variables:
```
JAVA_HOME=/path/to/java8
ANDROID_SDK_ROOT=/path/to/android_sdk_linux
ANDROID_NDK_ROOT=/path/to/android_ndk_linux
VEXE=/path/to/custom/v/binary
```

## Android SDK Setup

Until `vab` get support for setting up the complete dependency chain
you can avoid Android Studio by using commandline tools.

Android commandline tools can be downloaded from [here](https://developer.android.com/studio#command-tools)

Or with curl:

`curl -# --output commandlinetools-linux.zip https://dl.google.com/android/repository/commandlinetools-linux-6609375_latest.zip`

You can then use `sdkmanager` from that zip to install the Android SDK and NDK (NOTE these are quite huge downloads):
(If your default Java is **not** Java 8 - set `JAVA_HOME` before use)

`JAVA_HOME=/path/to/java sdkmanager "platform-tools" "platforms;android-21" "build-tools;29.0.3" "ndk;21.1.6352462"`

# Usage

You can build an Android app ready for the Play Store with the following command

```
export KEYSTORE_PASSWORD="pass"
export KEYSTORE_ALIAS_PASSWORD="word"
./vab -f -prod --name "V App" --package-id "com.example.app.id" --icon /path/to/file.png  --version-code <int> --keystore /path/to/sign.keystore --keystore-alias "example" /path/to/v/source/file/or/dir
```

You can also build debug builds and deploy directly to a device for testing
```
./vab --name "V App" --package-id "com.example.app.id" --device-id deadbeef /path/to/v/source/file/or/dir
```

**Complete list of env variables recognized**
```
JAVA_HOME
ANDROID_SDK_ROOT
ANDROID_NDK_ROOT
VEXE
ANDROID_SERIAL
KEYSTORE_PASSWORD
KEYSTORE_ALIAS_PASSWORD
```

See all options:
```
./vab -h
```