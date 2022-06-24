# Freqently Asked Questions

- [`vab` can't find my device when deploying?](#vab-cant-find-my-device-when-deploying)
- [The app force closes/crashes when I start it?](#the-app-force-closescrashes-when-i-start-it)
- [`vab` can't find my SDK/NDK/JAVA_HOME?](#vab-cant-find-my-SDKNDKJAVA_HOME)
- [I can't redirect (f)printf output to a file?](#i-cant-redirect-fprintf-output-to-a-file)
- [How do I load assets embedded in the APK/AAB?](#how-do-i-load-assets-embedded-in-the-apkaab)

## `vab` can't find my device when deploying?

You [need to enable debugging](https://developer.android.com/studio/command-line/adb#Enabling) on your device.
`vab` uses the `adb` tool from the SDK - you can check by running `adb devices`.

## The app force closes/crashes when I start it?

Make sure the device has an API level >= the API level used to build the app.
`vab` will use the highest API level available in the SDK per default. You can change
what API is used with the `--api <INT>` flag.
You can list all API's available with `vab --list-apis`.
Additionally connect your device via USB to your computer and run `vab` with the `--log` flag.
This should capture the logs relevant to the app in question.

## `vab` can't find my SDK/NDK/JAVA_HOME?

Currently `vab` doesn't support shell expansion of special
characters like the tilde character (`~`). So entries like these won't work:
* `ANDROID_SDK_HOME="~/Library/Android/Sdk"`
* `JAVA_HOME="~/dev/java"`

Instead please use full paths in env variables:
* `ANDROID_SDK_HOME="/Users/joe/Library/Android/Sdk"`
* `JAVA_HOME="/home/joe/dev/java"`

## I can't redirect (f)printf output to a file?

Per default `vab` will [enable `println()` and `eprintln()` output](https://github.com/vlang/v/blob/242b99340dec16ca8edb9f4392c873033162c242/thirdparty/sokol/sokol_v.pre.h#L1) to go to your device's system log
for easy access via `adb logcat` - this is done, for simplicity,
by redefining the C functions `printf` and `fprintf`.

To disable this behavior you can pass the `--no-printf-hijack` to `vab`.

## How do I load assets embedded in the APK/AAB?

Use `os.read_apk_asset('relative/path/to/assets/file') or { panic(err) }`

If you have a file `logo.png` in `assets/` - to load it, you need to call
`os.read_apk_asset('logo.png') or { panic(err) }`
