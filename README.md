# Usage
Dependencies: Java 8, Android SDK + NDK
```
git clone git@github.com:Larpon/v.git
cd v
git checkout feature/android-apk
make
cd ..
git clone git@github.com:Larpon/v-android-bootstrap.git
cd v-android-bootstrap

# From here you need to edit build.sh and set correct paths for the patched V, Java 8, Android SDK/NDK
# Or provide them via env variables:
#   ANDROID_SDK_ROOT=/path/to/android_sdk_linux
#   ANDROID_NDK_ROOT=/path/to/android_ndk_linux
#   JAVA_HOME=/path/to/java
#   V_HOME=/path/to/v/root

#   then:
./build.sh /path/to/v/examples/sokol/particles/main.v
```

## Android

If you want to avoid Android Studio you can use the commandline tools:
Android commandline tools can be downloaded from [here](https://developer.android.com/studio#command-tools)

Or with curl:
`curl -# --output commandlinetools-linux.zip https://dl.google.com/android/repository/commandlinetools-linux-6609375_latest.zip`

You can then use `sdkmanager` from that zip to install the Android SDK and NDK (WARNING huge downloads and install time!):
(If your default Java is **not** Java 8 - set `JAVA_HOME` before use)
`JAVA_HOME=/path/to/java sdkmanager "platform-tools" "platforms;android-21" "build-tools;29.0.3" "ndk;21.1.6352462"`