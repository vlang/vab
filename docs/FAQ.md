# Freqently Asked Questions

- [Where is the `examples` folder?](#where-is-the-examples-folder)
- [Generating `mipmap-xxxhdpi` icons in the APK/AAB](#generating-mipmap-xxxhdpi-icons-in-the-apkaab)
- [`vab` can't find my device when deploying?](#vab-cant-find-my-device-when-deploying)
- [The app force closes/crashes when I start it?](#the-app-force-closescrashes-when-i-start-it)
- [`vab` can't find my SDK/NDK/JAVA_HOME?](#vab-cant-find-my-SDKNDKJAVA_HOME)
- [I can't redirect (f)printf output to a file?](#i-cant-redirect-fprintf-output-to-a-file)
- [How do I load assets embedded in the APK/AAB?](#how-do-i-load-assets-embedded-in-the-apkaab)
- [I managed to compile some external .so libs,
how do I include them?](#i-managed-to-compile-some-external-so-libs-how-do-I-include-them)

## Where is the `examples` folder?

`vab` is able to build and run a lot of V's *graphical* examples out of the box.

V's graphical examples are typical those who import either `gg` or `sokol`.

Examples and apps using `$if android {...}` code constructs is typically a
good indicator of Android support.

Many examples in V's source distribution `examples/gg` and `examples/sokol` works.
Some examples in the top level `examples` directory also works, like `examples/2048`.

Note that not all of V's examples have been written with Android in mind and
may thus fail to compile or run properly, pull requests with Android fixes are
welcome.

## Generating `mipmap-xxxhdpi` icons in the APK/AAB

Per default `vab` tries to keep APK/AAB's as "slim" as possible.
So, per default, only one application icon is used/included when building packages.

If you want more icons for more screen sizes `vab` supports generating these when
packing everything up for distribution via the `--icon-mipmaps` flag.

When passing `--icon-mipmaps`, the icon mipmaps will be generated based on the
image passed via `--icon /path/to/icon.png`, or if `--icon` is *not* passed (or invalid),
`vab` will try and generate the mipmaps based on what image *may* reside in the
"package base files" "`res/mipmap"` directory.

For a vanilla build of `vab` the mipmap icons will thus be generated based on:
`platforms/android/res/mipmap/icon.png`

See [Package base files](https://github.com/vlang/vab/blob/master/docs/docs.md#package-base-files) for more info.

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

## I managed to compile some external .so libs, how do I include them?

Use the flag `--libs <path libs with arch(s) folder>` (can be specified multiple times)
to include extra libraries.

The libraries need to reside inside a folder with the name of the architecture they
are compiled for e.g.: `/tmp/libs/arm64-v8a` - this is normal and by convention for
other build systems used in Android development.

You can have one parent directory, containing libs for multiple archs:
```
/tmp/libs/arm64-v8a/libmain.so
/tmp/libs/armeabi-v7a/libmain.so
/tmp/libs/x86/libmain.so
```
... in which case passing `--libs /tmp/libs` will include *all* of the libs found under `/tmp/libs`.
