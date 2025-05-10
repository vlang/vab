## vab up

(Features available with latest build from source)

#### Notable changes

Allow for compile-time tweaks of default values:
* `default_app_name` via `-d vab:default_app_name='V Test App'`
* `default_package_id` via `-d vab:default_package_id='io.v.android'`
* `default_activity_name` via `-d vab:default_activity_name='VActivity'`
* `default_package_format` via `-d vab:default_package_format='apk'`
* `default_min_sdk_version` = `-d vab:default_min_sdk_version=21`
* `default_base_files_path` via `-d vab:default_base_files_path=''`

Add support for generating APK/AAB icon mipmaps.

##### Example

```bash
vab --icon-mipmaps --icon ~/v/examples/2048/demo.png ~/v/examples/2048 -o /tmp/2048.apk
unzip -l /tmp/2048.apk # Should list "res/mipmap-xxxhdpi/icon.png" etc. entries
```

## vab 0.4.3
*11 October 2024*

#### Notable changes

Added support for command-line *extra commands*.

##### Example

Compile `vab` with *extra command* support (needed to execute installed commands):
```bash
v -d vab_allow_extra_commands ~/.vmodules/vab
```

Install an extra command (Example `larpon/vab-sdl` that supports building SDL based V apps for Android):
```bash
vab install extra larpon/vab-sdl
vab doctor # Should show a section with installed extra commands where `vab-sdl` should show.
```

Call the extra command (needs `vlang/sdl` module installed and working):
```bash
vab sdl ~/.vmodules/sdl/examples/tvintris -o /tmp/tvintris.apk
```

#### Commits

* vab: add `--version` flag (#321)
* extra: support install/remove from local sources (#320)
* all: support *extra commands*, `vab <cmd>` where `<cmd>` comes from `vab install extra user/vab-<cmd>` (#319)
* deploy: add notice below (potential) long crash reports (#318)
* vab: introduce and use `paths` module (#316)

## vab 0.4.2
*01 October 2024*

#### Notable changes

Start using a change log.
Added `vab.android.emulator` module for basic emulator control

#### Commits

* platforms: minor format unification in `AndroidManifest.xml` (#291)
* options, deploy: fix setting `device_id` when `verbosity <= 1` (#293)
* vab, cli: refactor flag parsing, deprecate programmatic `flag.FlagParser` usage (#294)
* ci: update GitHub action versions to prevent warnings (#295)
* all: run `v fmt -w .` in project root (#296)
* vab, cli: minimize special handling of input in user space (#297)
* cli, options: simplify special case handling, pass unknown flags to caller/`opt.additional_args` (#298)
* cli, tests: fix `input_from_args`, fix cli tests (#299)
* vab: colored errors, warnings, notices, shorter `opt.verbosity` print statements (#300)
* cli, compile: support `-no-bounds-checking` v flag (#301)
* util: show job error when failing in `run_jobs` (#302)
* cli: fail better on V style flag parsing (#303)
* options: use `ANDROID_SERIAL` env variable as default `device_id` (#304)
* docs: add FAQ entry about examples (#306)
* all: run `v fmt -w .` in project root (is `vfmt` drunk?) (#305)
* ci: remove obsolete cancel job, use concurrency group names from V CI (#307)
* env: add preliminary emulator support (#308)
* tests: add + support runtime tests (#309)
* ci, emulator: use `actions/checkout` to install V and examples in one go (#310)
* ci, tests: ignore `notice:` in error tests more gracefully (#311)
* ci: use faster `aosp_atd` avd variant instead of `google_apis` in legacy emulator (#312)
* ci: use `ubuntu-latest` on steps: `code-formatting`, `v-compiles-os-android` (#313)
* deploy: trigger `logcat -c` *after* package installs, increase sleeps a bit (#314)
* env, ci: add support for linux emulator runs, add new `emulator` module (#315)
