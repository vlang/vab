# Manually bootstrapping a bare minimum Android development setup

These instructions is aimed at Android developers that know the history
and advanced usages of the Android SDK.

Do not follow the below instructions if you do not know how the commend-line tool
bootstrapping process of the Android SDK works. If something changes after this
write-up is released it can leave you with a broken SDK,
hence it is recommended that users use their existing Android SDK or use `vab install auto`.

---

The following steps describe how to *manually* bootstrap a minimal setup that can be used to
build and release native apps for Android. The setup is not specific to `vab`, it should
work for any Android development purpose trying to avoid Android Studio. It works much
the same as `vab install auto` but describes the process in more detail.

The instructions assume you **do** have Java installed (see [README.md](../README.md#Java) for
install instructions) the instructions also assume that you **do not** have any
Android SDK or NDK already installed. Do not install multiple Android SDKs unless you have
experience with handling such setups.

A bare minimum setup requires the Android SDK "Command line tools" package. Once
installed the rest of the Android SDK + NDK can be installed via the tool `sdkmanager`.

Start by navigating to [https://developer.android.com/studio#command-tools](https://developer.android.com/studio#command-tools)
and locate a section named "Command line tools only" (or similar) and download the
"SDK tools package" for your platform. E.g.: `commandlinetools-linux-10406996_latest.zip`.

Once downloaded, decide a location you want your Android SDK to reside in. In this example
we use `$HOME/Android/Sdk`. The following (bash) command history will give you a fully working
Android SDK, it can be adjusted to fit your setup:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"
unzip commandlinetools-linux-10406996_latest.zip -d "/tmp"
mv "/tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
export SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
"$SDKMANAGER" --version # test that sdkmanager works
"$SDKMANAGER" "platform-tools" "build-tools;34.0.0" "platforms;android-33" "ndk;22.1.7171670" # install ADB etc., build-tools, a platform and the NDK in one go
```

For a persistent setup you can add the SDK tools to your `PATH` variable
via `.profile` or `.bash_profile` like so:

```bash
echo 'export PATH=${PATH}:'"$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools" >> "$HOME/.profile"
```
