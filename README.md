# V Android Bootstrapper

V Android Bootstrapper (`vab`) is the currently supported way
to compile, package, sign and deploy V graphical apps on Android
based devices.

# Install
Currently Linux and macOS build hosts are supported.
Dependencies: V, Java (JDK) 8, Android SDK + NDK (**no** Android Studio required)
```
git clone git@github.com:Larpon/vab.git
cd vab
v vab.v
```

If `vab` fail to detect your environment you can set ENV variables
to help it:
```
JAVA_HOME=/path/to/java-8-jdk
ANDROID_SDK_ROOT=/path/to/android_sdk_linux
ANDROID_NDK_ROOT=/path/to/android_ndk_linux
VEXE=/path/to/custom/v/binary
```

# Usage

## Development (debug builds)

The fast way from source to device (build, package, deploy and launch app) is:
```
./vab run --device auto --archs 'armeabi-v7a' /path/to/v/source/file/or/dir
```

## Release

You can build an Android app ready for the Play Store with the following command:
```
export KEYSTORE_PASSWORD="pass"
export KEYSTORE_ALIAS_PASSWORD="word"
./vab -prod --name "V App" --package-id "com.example.app.id" --icon /path/to/file.png  --version-code <int> --keystore /path/to/sign.keystore --keystore-alias "example" /path/to/v/source/file/or/dir
```


**Complete list of env variables recognized**
```
VEXE                     # Absolute path to the V executable to use
JAVA_HOME                # Absolute path to the Java install to use
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

`vab` now has support for guiding and downloading it's dependencies automatically, except the Java 8 JDK.

If you have nerves to let it try and figure things out automatically simply do:
`vab install auto`

## Java 8

### macOS
Installing Java 8 using homebrew
```
brew tap adoptopenjdk/openjdk
brew cask install adoptopenjdk8
```

### Linux
You should be able to find a way to install Java 8 JDK with your package manager of choice.

E.g.:
```
sudo apt install openjdk-8-jdk
```

# Notes
`vab` targets as low an API level as possible by default for maximum compatibility, you can however tell it to target newer Android versions by using the `--api` flag. Example: `vab --api 30 <...>`.
Installed API levels can be listed with `vab --list-apis`.
