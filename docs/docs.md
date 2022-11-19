Please contribute to this document if you think something is missing or could be better.

`vab` is basically just a wrapper around the Android SDK and NDK. `vab` is able to both
install, locate and orchestrate the tools found inside the distributed development kits.

Welcome - and have a productive time using V and `vab`!

# Contents

- [Introduction](#introduction)
- [The V to Android App Development Cycle](#the-v-to-android-app-development-cycle)
- [Using `vab` from the command line](#using-vab-from-the-command-line)
- [Using `vab` programmatically](#using-vab-programmatically)
- [Examples](#examples)
- [Compile V code to Android Compatible C code](#compile-v-code-to-android-compatible-c-code)
- [Compile C code to Android shared library (.so)](#compile-c-code-to-android-shared-library-so)
- [Find and Invoke NDK Compiler Manually](#find-and-invoke-ndk-compiler-manually)

# Introduction

Android is a, primarily, Java based Operating System - and to be able to develop apps for
*the majority* of devices on the market (2022), the primary option is to target Google-based
Android devices.

To be able to develop for Google-based devices, Google provide the *Android SDK*, and
for native developement (C/C++), they provide the *Android NDK*. Both are currently required
to be able to develop Android apps in V.

While the Android OS itself is open source - the SDK and NDK distributed by Google are ***not***.
This fact makes everything a bit harder than it ought to be.

So - for us to target the majority, we need the Android SDK and NDK that are
both proprietary licensed in such a way that they prevent developers from
modifying and re-distributing them - thus forcing developers to use Google's
official (rather large) distributions of these developement kits.

For historical reasons - the job of locating and using all the tools in the
development kits is actually harder than it might appear at first sight
since Google tend to move things around, deprecate tools on short, if any, notice
and, in general, always be in a kind of "beta" mode when they release the software
needed to target and build for the Google flavoured Android OS devices.

To compensate for this they've developed a ~900MiB tool called "Android Studio"
to aid developers in developing for their platform... Because of it's huge size,
slow compile speeds and the difficulties involved in integrating a satisfying user
experience for, at least, V developers - V has chosen to develop a tool that
completely eliminate the need to use Android Studio in V development.

With all this in mind `vab` was born to make life easier for V developers.
You can install it by following the instructions [in the README.md](https://github.com/vlang/vab#install).

# The V to Android App Development Cycle

A typical V Android app development cycle will, roughly, include the following steps:

1. Develop an app in V (using `$if android {...}` for Android specific code).
2. Compile the V code to Android compatible C code (`v -os android -o code.c ...`).
3. Compile Android compatible C code to a *shared* library (`.so`) with a NDK compiler.
4. Prepare all base files (e.g. `AndroidManifest.xml`, Java activity sources, etc.)
needed for the Android app to be able to start on the device OS.
5. Compile Java sources to load and bootstrap the *shared* library + any Java dependencies required.
6. Package everything up for distribution via an `.apk` or `.aab` archive
(dex sources, copy native libs etc.).
7. Sign the packaged `.apk`/`.aab` with a keytool.
8. (Optionally) deploy and/or run the app on an emulator or physical device.
9. (Optionally) debug the app (via `adb logcat ...`).

The developer is expected to take care of bullet point `1.` while `vab` will help cover the rest.

# Using `vab` from the command line

For now please use the [Usage](https://github.com/vlang/vab#usage) section of the README.md
and the [FAQ.md](https://github.com/vlang/vab/blob/master/docs/FAQ.md).

# Using `vab` programmatically

Please keep in mind that using `vab` programmatically has the same
prerequisites as using the `vab` command line tool. Use `vab doctor` on the command line
to check if all dependencies are met and setup correctly.

You can also invoke the `doctor` programmatically:

```v ignore
import vab.cli

cli.doctor(...)
```

On top, it's *recommended* that you have some experience with Android development already,
as some terms and situations can be resolved more quickly with knowledge about the different
areas and implications of Android developement.

In some situations, calling `vab` from the command line might not fit
a specific project, setup or problem at hand. You usually want more control
and flexibility - fear not - this is why `vab` is also exposed as a module (`import vab.xxx`).

The most useful modules are the following:

```v oksyntax
import vab.cli // For easy replication of the `vab` command line tool
import vab.android // For invoking the major steps: compile, package and deploy
import vab.android.sdk // For easy access to tools in the Android SDK
import vab.android.ndk // For easy access to tools in the Android NDK
```

For general programmatic usage see the relatively small [`vab.v`](https://github.com/vlang/vab/blob/master/vab.v), that makes up the command line tool.
It shows the *major* steps you need to take, to get from V source code to a running Android app.

Working with native code like C (and implicitly V) on Android can get a little
cumbersome when things doesn't fit into the usual boxes, especially because the smallest
things can often touch and affect *all* the different stages in developing an
Android application. `vab` is designed with this in mind, to be able handle each of
these stages as flexible and easy as possible.

By using `vab` as a module you get access to both the high-level operations
(compile, package, deploy) as well as fine grained control if you, for example,
just want to compile a C file with a specific NDK compiler or locate the path(s) to
the SDK or NDK on your host computer.

(See examples for V snippets on how to do certain, popular, tasks).

The high-level program logic for doing most of the work is implemented in the files
[`android/compile.v`](https://github.com/vlang/vab/blob/master/android/compile.v),
[`android/package.v`](https://github.com/vlang/vab/blob/master/android/package.v) and
[`android/deploy.v`](https://github.com/vlang/vab/blob/master/android/deploy.v).

If you're in doubt how some call is supposed to work - the source code of
these functions is a good place to discover *how* things, in general, are
used and in what *order* they should be invoked.

They basically contain a function for each *major* step of the process:
```v ignore
import vab.android

// Compile V source to C source, and C source to a shared library
compile_opt := android.CompileOptions{
    ...
}
android.compile(compile_opt) or { panic(err) }

// Prepare base files, compile Java sources, package everything up in a .apk/.aab
package_opt := android.PackageOptions{
    ...
}
android.package(package_opt) or { panic(err) }

// Deploy the package to an emulator or device
deploy_opt := android.DeployOptions{
    ...
}
android.deploy(deploy_opt) or { panic(err) }
```

# Examples

The following are some useful examples, please contribute to this section if you think something
is missing or could be better. All examples assumes that you have *a working* install of `vab`.

## Compile V code to Android Compatible C code

It is important to keep in mind that most (if not all?) C libs that control the
app window and (OpenGL) acceleration context, usually have framework-like behavior on Android, which
means that they usually require full authority over the way they start up and open the
[NativeActivity](https://developer.android.com/ndk/reference/group/native-activity) which is the entry point for *native* graphical apps.

This is often the reason why a lot of fiddling is required to get C libs like `SDL2`, `sokol_app`
and `RayLib` mixed with V code; *All of them* want control over how the window/context is opened.

Luckily V allows for outputting code which is agnostic to who or what will open the window.

From the command line, this is basically just invoking the `v` compiler
with the right set of flags for Android:

```bash
v -os android -o code.c source.v
```
A few nice to know flags, in regards to the window/context issue noted above, is especially
the `-apk` and `-d no_sokol_app` flags.

The former, `-apk`, tells V that we want to prepare the code for packaging - this implies that
code is generated to support V's graphical backend (`gg`/`sokol.app`) - this means that
V will take control of the window opening and acceleration context.

Sometimes you want your code to compile for other frameworks like e.g. RayLib or SDL2
in this case you'll need the former, `-d no_sokol_app` flag.
This makes sure that V doesn't take control of the initial window opening process
leading the way for e.g. SDL2 or RayLib to control it instead.

If you want to do this *programmatically* you can use
the following V code to use `vab` to produce it.

(For a real life example see the body of [`this function`](https://github.com/vlang/vab/blob/f06e67cf/android/compile.v#L112))


```v oksyntax
import os
import vab.android

opt := android.CompileOptions{
	work_dir: os.temp_dir()
	// For all options, see link below.
	//
	// You will find that options passed to the command line `vab` is
	// named very closely after the fields in the config structs - to make
	// it as easy as possible to follow the flags around the program.
}
android.compile_v_to_c(opt) or { panic(err) }
```
[`android.CompileOptions`](https://github.com/vlang/vab/blob/f06e67cf/android/compile.v#L21-L39).

Running the above will produce `/tmp/v_android.c`, an Android compatible C file
that can be compiled by a NDK compiler.

## Compile C code to Android shared library (.so)

In the section above we produced Android compatible C code. Now we want to compile that into
a shared library that any Java activity can load via [`System.loadLibrary()`](https://github.com/vlang/vab/blob/f06e67cf/platforms/android/src/io/v/android/VActivity.java#L6).

In theory the C code doesn't have to be produced by V - it can be any
Android compatible C source code, `vab` does, however, adjust some compile flags that
suit V code better, depending on what you pass in as options to the `compile` function.

```v
import os
import vab.android

opt := android.CompileOptions{
	work_dir: os.temp_dir()
	// For all options, see link below.
	//
	// no_so_build: true // Use this if you only want to generate object files (.o) and no shared lib (.so)
}
android.compile(opt) or { panic(err) }
```
[`android.CompileOptions`](https://github.com/vlang/vab/blob/f06e67cf/android/compile.v#L21-L39).

The above produces files in
`/tmp/build/lib/<arch>/lib<name from opt>.so` and `/tmp/build/o/<arch>/<source name>.o`

If you just want to locate a compiler in the NDK and invoke it, see the next example.

## Find and Invoke NDK Compiler Manually

If you just want to locate a compiler from the NDK and invoke it manually,
passing everything in yourself - you can use something like the following:

```v
import os
import vab.android.ndk

// Get the path to a C compiler.
//
// `ndk_version` should be the *full* version as indicated by the *directory name* where your NDK resides.
// Available versions detected can be retrieved with:
// `list := ndk.versions_available()`
// If you don't care you can get a default by running:
ndk_version := ndk.default_version()

// Request a C compiler for API level 21 for architecture arm64-v8a from the NDK.
compiler := ndk.compiler(.c, ndk_version, 'arm64-v8a', '21') or { panic(err) }

// Get recommended, Android specific, flags (also used by e.g. Gradle) for the compiler
// Make sure they fit the compiler you're targeting.
compiler_flags := ndk.compiler_flags_from_config(ndk_version,
	arch: 'arm64-v8a'
	lang: .c
	debug: true // false = if you want production flags (-prod)
	cpp_features: ['no-rtti', 'no-exceptions'] // Special features available for C++ compilers, ignored for C compilers
) or { panic(err) }

// Flatten the flags
flags := compiler_flags.flags.join(' ')

// If you're linking, the linker flags can be obtained via the `ld_flags` field:
// ld_flags := compiler_flags.ld_flags.join(' ')

// Invoke the compiler
os.execute('${compiler} ${flags} -my-other-flags -c input.c -o out.o')
```

See [`ndk.v`](https://github.com/vlang/vab/blob/master/android/ndk/ndk.v) for more functions.