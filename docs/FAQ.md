# Freqently Asked Questions

- [`vab` can't find my device when deploying?](#vab-cant-find-my-device-when-deploying)
- [The app force closes/crashes when I start it?](#the-app-force-closescrashes-when-i-start-it)
- [`vab` can't find my SDK/NDK/JAVA_HOME?](#vab-cant-find-my-SDKNDKJAVA_HOME)

## `vab` can't find my device when deploying?

You [need to enable debugging](https://developer.android.com/studio/command-line/adb#Enabling) on your device.
`vab` uses the `adb` tool from the SDK - you can check by running `adb devices`.

## The app force closes/crashes when I start it?

Make sure the device has an API level >= the API level used to build the app.
`vab` will use the highest API level available in the SDK per default. You can change
what API is used with the `--api <INT>` flag. You can list all API's available with `vab --list-apis`.
Additionally connect your device via USB to your computer and run `vab` with the `--log` flag.
This should capture the logs relevant to the app in question.

## `vab` can't find my SDK/NDK/JAVA_HOME?

Currently `vab` doesn't support shell expansion of special characters like the tilde character (`~`).
So entries like these won't work:
* `ANDROID_SDK_HOME="~/Library/Android/Sdk"`
* `JAVA_HOME="~/dev/java"`

Instead please use full paths in env variables:
* `ANDROID_SDK_HOME="/Users/joe/Library/Android/Sdk"`
* `JAVA_HOME="/home/joe/dev/java"`
