## vab 0.4.2
*01 October 2024*

#### Notable changes

Start using a change log.
Added `vab.android.emulator` module for basic emulator control

#### Commits

platforms: minor format unification in `AndroidManifest.xml` (#291)
options, deploy: fix setting `device_id` when `verbosity <= 1` (#293)
vab, cli: refactor flag parsing, deprecate programmatic `flag.FlagParser` usage (#294)
ci: update GitHub action versions to prevent warnings (#295)
all: run `v fmt -w .` in project root (#296)
vab, cli: minimize special handling of input in user space (#297)
cli, options: simplify special case handling, pass unknown flags to caller/`opt.additional_args` (#298)
cli, tests: fix `input_from_args`, fix cli tests (#299)
vab: colored errors, warnings, notices, shorter `opt.verbosity` print statements (#300)
cli, compile: support `-no-bounds-checking` v flag (#301)
util: show job error when failing in `run_jobs` (#302)
cli: fail better on V style flag parsing (#303)
options: use `ANDROID_SERIAL` env variable as default `device_id` (#304)
docs: add FAQ entry about examples (#306)
all: run `v fmt -w .` in project root (is `vfmt` drunk?) (#305)
ci: remove obsolete cancel job, use concurrency group names from V CI (#307)
env: add preliminary emulator support (#308)
tests: add + support runtime tests (#309)
ci, emulator: use `actions/checkout` to install V and examples in one go (#310)
ci, tests: ignore `notice:` in error tests more gracefully (#311)
ci: use faster `aosp_atd` avd variant instead of `google_apis` in legacy emulator (#312)
ci: use `ubuntu-latest` on steps: `code-formatting`, `v-compiles-os-android` (#313)
deploy: trigger `logcat -c` *after* package installs, increase sleeps a bit (#314)
env, ci: add support for linux emulator runs, add new `emulator` module (#315)
