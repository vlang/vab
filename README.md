# V Android Bootstrapper

[Home](https://github.com/vlang/vab) • [Docs](docs/docs.md) • [FAQ](docs/FAQ.md)

V Android Bootstrapper is the currently supported way
to compile, package, sign and deploy V graphical apps on Android
based devices. It can be used as a V module (`import vab`) and also
provides a standalone executable (`vab`) for building apps from the command-line.

<img src="https://user-images.githubusercontent.com/768942/107622846-c13f3900-6c58-11eb-8a66-55db12979b73.png">

# Install

Linux, macOS and Windows build hosts are supported.

### Unix (Linux, macOS)
```bash
v install vab
v ~/.vmodules/vab
```

### Windows
```bash
v install vab
v %USERPROFILE%\.vmodules\vab
```

## Symlink (optional)
You can symlink `vab` to your `$PATH` so it works as a global shell command.

```bash
sudo ln -s /path/to/vab /usr/local/bin/vab
```

## Shell tab completion (optional)
You can install tab completions for your shell by [following the instructions
here](https://github.com/vlang/vab/blob/3091ade4c9792c6a37596ccfa9299fb269d3160e/cmd/complete.v#L11-L38).

# Usage

`vab` can be used both from the command line and as a module in V code.
In either case the following dependencies is required before `vab` will work
as intented.

## Runtime dependencies
 * V
 * Java (JDK) >= 8 (>= 9 on Windows)
 * Android SDK
 * Android NDK

(Android Studio is **NOT** required)

If `vab` fail to detect your environment you can set ENV variables
to help it:
```bash
JAVA_HOME=/path/to/java-jdk
SDKMANAGER=/path/to/sdkmanager
ANDROID_SDK_ROOT=/path/to/android_sdk_linux
ANDROID_NDK_ROOT=/path/to/android_ndk_linux
VEXE=/path/to/custom/v/binary
```

## Development (debug builds)

The fast way from V source to an APK is:
```bash
vab /path/to/v/source/file/or/dir
```
... yes, that's it. Your APK should now reside in the current directory.

The fast way from source to a run on the device
(build, package, deploy and launch app on device) is:
```bash
vab run --device auto --archs 'armeabi-v7a' /path/to/v/source/file/or/dir
```
The `--archs` flag control what architectures your app is built for.
You can specify multiple archs with `--archs 'armeabi-v7a, arm64-v8a'`.
By default `vab` will build for all 4 supported
CPU architectures (`arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`).

## Release

You can build an Android app ready for the Play Store with the following command:
```bash
export KEYSTORE_PASSWORD="pass"
export KEYSTORE_ALIAS_PASSWORD="word"
vab -prod --name "V App" --package-id "com.example.app.id" --icon-mipmaps --icon /path/to/file.png  --version-code <int> --keystore /path/to/sign.keystore --keystore-alias "example" /path/to/v/source/file/or/dir
```
Do not submit apps using default values.
Please make sure to adhere to all [guidelines](https://developer.android.com/studio/publish) of the app store you're publishing to.

## AAB package format

`vab` supports outputting [Android App Bundles](https://developer.android.com/guide/app-bundle) (AAB).
To output an `.aab` file you can specify the package format with the `--package` flag:

```bash
vab --package aab /path/to/v/source/file/or/dir
```

Alternatively it will be inferred if you use the `--output`/`-o` flag:
```bash
vab -o /tmp/ma_app.aab /path/to/v/source/file/or/dir
```

# Environment variables

If `vab` should fail to detect a tool or location on your build host
you can use the following ENV variables to help `vab` understand your
Android development setup.

**Complete list of env variables recognized**
```bash
VEXE                     # Absolute path to the V executable to use
JAVA_HOME                # Absolute path to the Java install to use
SDKMANAGER               # Absolute path to the sdkmanager to use
ANDROID_SERIAL           # ID of the device to deploy to
ANDROID_SDK_ROOT         # Absolute path to the Android SDK
ANDROID_NDK_ROOT         # Absolute path to the Android NDK
KEYSTORE_PASSWORD        # Password for keystore
KEYSTORE_ALIAS_PASSWORD  # Password for keystore alias
BUNDLETOOL               # Absolute path to the bundletool to use
AAPT2                    # Absolute path to the aapt2 to use
ADB                      # Absolute path to the adb to use
AVDMANAGER               # Absolute path to the avdmanager to use
EMULATOR                 # Absolute path to the emulator to use
```

```bash
VAB_EXE                  # Absolute path to a vab executable (Used in tests and sub-cmd execution)
VAB_FLAGS                # Used to pass flags to vab. Command-line flags overwrites any flags/values set via VAB_FLAGS.
VAB_KILL_ADB             # Set to let vab kill adb after use. This is useful on some hosts.
```

## `VAB_FLAGS` example:
`VAB_FLAGS="-v 3 --name 'V App' --api 30 --build-tools 29.0.0" vab /path/to/v/source/file/or/dir`

See all options:
```bash
vab -h
```

# Setup

`vab` has support for downloading it's dependencies automatically, except the Java JDK.

If you have nerves to let it try and figure things out automatically simply do:
`vab install auto`

## Java

### Windows

OpenJDK can be installed via [https://adoptium.net/](https://adoptium.net/).

### macOS

Installing Java JDK using homebrew

```bash
brew tap adoptopenjdk/openjdk
brew cask install adoptopenjdk
```

### Linux

You should be able to find a way to install Java JDK >= 8 with your package manager of choice.

```bash
sudo apt install openjdk-<version>-jdk
```

E.g.: `sudo apt install openjdk-8-jdk`

### termux (experimental)

**NOTE** Currently only tested for `arm64` on Android 9 and above.

You must install Java 17 and few more things:

```bash
pkg install openjdk-17 aapt apksigner dx ecj
```

Download, unzip and set enviroment variables to the SDK and NDK from:

[https://github.com/Lzhiyong/termux-ndk/releases](https://github.com/Lzhiyong/termux-ndk/releases).

You may have to set the SDK version to be compatible with the NDK
(`sdkmanager install/uninstall platform-version`).

Enjoy using vab on `termux`!

[@MatejMagat305](https://github.com/MatejMagat305) has made a video of the process you can watch here:

[https://www.youtube.com/watch?v=7aUh39w_-2Q](https://www.youtube.com/watch?v=7aUh39w_-2Q).

The accompaning script used in the video can be found here:

[https://github.com/MatejMagat305/vab-termux](https://github.com/MatejMagat305/vab-termux).

# Examples

See [*"Where is the `examples` folder?"*](docs/FAQ.md#where-is-the-examples-folder)
in the [FAQ](docs/FAQ.md).

# Tests

`vab`, like many other V modules, can be tested with `v test .`.

Note that `vab` has *runtime* tests that requires all [runtime dependencies](#runtime-dependencies)
to be installed in order for the tests to run correctly.
Runtime tests can be run with `vab test-runtime` (also part of `vab test-all`).

# Extending `vab`

The `vab` command-line tool can be extended with custom user commands.
See the "[Extending `vab`](docs/docs.md#extending-vab)" section
in the [documentation](docs/docs.md).

# Notes

`vab` targets as low an API level as possible by default for maximum
compatibility, you can however tell it to target newer Android versions
by using the `--api` flag. Example: `vab --api 30 <...>`.

Installed API levels can be listed with `vab --list-apis`.

# Troubleshooting

Android is a complex ecosystem that has differences between
build hosts and tool versions - consult our [FAQ](docs/FAQ.md)
for answers to frequently asked questions.
