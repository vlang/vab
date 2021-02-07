# V Android Bootstrapper

V Android Bootstrapper (`vab`) is the currently supported way
to compile, package, sign and deploy V graphical apps on Android
based devices.

# Install

Currently Linux and macOS build hosts are supported.
Dependencies:
 * V
 * Java (JDK) >= 8
 * Android SDK
 * Android NDK

(**no** Android Studio required)

```
git clone https://github.com/vlang/vab.git
cd vab
v vab.v
```

If `vab` fail to detect your environment you can set ENV variables
to help it:
```
JAVA_HOME=/path/to/java-jdk
SDKMANAGER=/path/to//sdkmanager
ANDROID_SDK_ROOT=/path/to/android_sdk_linux
ANDROID_NDK_ROOT=/path/to/android_ndk_linux
ANDROID_SERIAL=<device id>
VEXE=/path/to/custom/v/binary
```

# Usage

## Development (debug builds)

The fast way from V source to an APK is:
```
./vab /path/to/v/source/file/or/dir
```
... yes, that's it. Your APK should now reside in the current directory.

The fast way from source to a run on the device (build, package, deploy and launch app on device) is:
```
./vab run --device auto --archs 'armeabi-v7a' /path/to/v/source/file/or/dir
```
The `--archs` flag control what architectures your app is built for.
You can specify multiple archs with `--archs 'armeabi-v7a, arm64-v8a'`.
By default `vab` will build for all 4 supported CPU architectures (`arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`).

## Release

You can build an Android app ready for the Play Store with the following command:
```
export KEYSTORE_PASSWORD="pass"
export KEYSTORE_ALIAS_PASSWORD="word"
./vab -prod --name "V App" --package-id "com.example.app.id" --icon /path/to/file.png  --version-code <int> --keystore /path/to/sign.keystore --keystore-alias "example" /path/to/v/source/file/or/dir
```
Do not submit apps using default values.
Please make sure to adhere to all [guidelines](https://developer.android.com/studio/publish) of the app store you're publishing to.

**Complete list of env variables recognized**
```
VEXE                     # Absolute path to the V executable to use
JAVA_HOME                # Absolute path to the Java install to use
SDKMANAGER               # Absolute path to the sdkmanager to use
ANDROID_SDK_ROOT         # Absolute path to the Android SDK
ANDROID_NDK_ROOT         # Absolute path to the Android NDK
KEYSTORE_PASSWORD        # Password for keystore
KEYSTORE_ALIAS_PASSWORD  # Password for keystore alias

VAB_KILL_ADB             # Set to let vab kill adb after use. This is useful on some hosts.
```

See all options:
```
./vab -h
```

# Setup

`vab` has support for downloading it's dependencies automatically, except the Java JDK.

If you have nerves to let it try and figure things out automatically simply do:
`vab install auto`

## Java

### macOS

Installing Java JDK using homebrew

```
brew tap adoptopenjdk/openjdk
brew cask install adoptopenjdk
```

### Linux

You should be able to find a way to install Java JDK >= 8 with your package manager of choice.

```
sudo apt install openjdk-<version>-jdk
```

E.g.: `sudo apt install openjdk-8-jdk`

# Notes

`vab` targets as low an API level as possible by default for maximum compatibility, you can however tell it to target newer Android versions by using the `--api` flag. Example: `vab --api 30 <...>`.
Installed API levels can be listed with `vab --list-apis`.

# Troubleshooting

Android is a complex ecosystem - please consult our [FAQ](docs/faq.md) for answers to frequently asked questions.
