# Freqently Asked Questions

- [`vab` can't find my device when deploying?](#vab-cant-find-my-device-when-deploying)
- [The app force closes/crashes when I start it?](#the-app-force-closescrashes-when-i-start-it)

## `vab` can't find my device when deploying?

You [need to enable debugging](https://developer.android.com/studio/command-line/adb#Enabling) on your device.
`vab` uses the `adb` tool from the SDK - you can check by running `adb devices`.

## The app force closes/crashes when I start it?

Make sure the device has an API level >= the API level used to build the app.
`vab` will use the highest API level available in the SDK per default. You can change
what API is used with the `--api <INT>` flag. You can list all API's available with `vab --list-apis`.
Additionally connect your device via USB to your computer and run `vab` with the `--log` flag.
This should capture the logs relevant to the app in question.
