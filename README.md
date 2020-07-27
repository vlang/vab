
Dependencies: Java 8, Android SDK + NDK
```
git clone git@github.com:Larpon/v.git
cd v
git checkout feature/android-apk
v self

cd ..
git clone git@github.com:Larpon/v-android-bootstrap.git
cd v-android-bootstrap

# Here you need edit build.sh and set correct paths for Java/Android SDK/NDK
# Or provide them via env variables:
#   ANDROID_SDK_ROOT=/path/to/android_sdk_linux
#   ANDROID_NDK_ROOT=/path/to/android_ndk_linux
#   JAVA_HOME=/path/to/java
#   V_HOME=/path/to/v/root

#   then:

./build.sh /path/to/v/examples/sokol/particles/main.v
```