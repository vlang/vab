module cli

import os
import flag
import semver
import vab.java
import vab.android
import vab.android.sdk
import vab.android.ndk
import vab.android.env

// Options represents all possible configuration that `vab` works with.
// Most fields can be mapped from commandline flags. The ones that can not
// are marked with `@[ignore]` and are usually parsed differently or computed at later stages.
// For fields missing documentation, see the const `vab_documentation_config`.
pub struct Options {
pub:
	// These fields would make little sense to change during a run
	verbosity       int    @[short: v; xdoc: 'Verbosity level (1-3)']
	work_dir        string = work_directory @[ignore]
	run_builtin_cmd string @[ignore] // run a command from subcmd_builtin (e.g. `vab doctor`)
	// Build, packaging and deployment
	parallel     bool = true @[long: 'no-parallel'; xdoc: 'Do not run tasks in parallel.']
	cache        bool = true @[long: 'nocache'; xdoc: 'Do not use build cache']
	gles_version int  = android.default_gles_version  @[long: gles; xdoc: 'GLES version to use']
	// Deploy specifics
	run              bool @[ignore] // run is handled separately in argument parsing
	device_log       bool @[long: 'log'; xdoc: 'Enable device logging after deployment.']
	device_log_raw   bool @[long: 'log-raw'; xdoc: 'Enable unfiltered, full device logging after deployment.']
	clear_device_log bool @[long: 'log-clear'; xdoc: 'Clear the log buffer on the device before deployment.']
	// Detected environment
	dump_usage       bool @[long: 'help'; short: h; xdoc: 'Show this help message and exit']
	list_ndks        bool @[xdoc: 'List available NDK versions']
	list_apis        bool @[xdoc: 'List available API levels']
	list_build_tools bool @[xdoc: 'List available Build-tools versions']
	list_devices     bool @[xdoc: 'List available device IDs (including running emulators)']
	// screenshot functionality
	screenshot                string @[xdoc: 'Take a screenshot on a device and save it to /path/to/file.png or /path/to/directory']
	screenshot_delay          f64    @[xdoc: 'Wait for this amount of seconds before taking screenshot']
	screenshot_on_log         string @[xdoc: 'Wait for this string to appear in the device log before taking a screenshot']
	screenshot_on_log_timeout f64 = -1.0    @[xdoc: 'Timeout after this amount of seconds if --screenshot-on-log string is not detected']
pub mut:
	// I/O
	input           string   @[tail] // NOTE: vab also supports passing input as *first* argument
	output          string   @[short: o; xdoc: 'Path to output (dir/file)']
	additional_args []string @[ignore] // additional_args collects arguments (*not* flags) that could not be parsed
	// App essentials
	app_name               string = android.default_app_name @[long: name; xdoc: 'Pretty app name']
	icon                   string @[xdoc: 'App icon']
	package_id             string = android.default_package_id @[xdoc: 'App package ID (e.g. "org.company.app")']
	activity_name          string @[xdoc: 'The name of the main activity (e.g. "VActivity")']
	package_format         string = android.default_package_format @[long: package; xdoc: 'App package format (.apk/.aab)']
	package_overrides_path string @[long: 'package-overrides'; xdoc: 'Package file overrides path (e.g. "/tmp/java")']
	// Build and packaging
	archs                   []string = android.default_archs @[ignore] // Compile for these archs. (parsed specially to support "arch,arch,arch")
	is_prod                 bool     @[ignore] // Parsed and inferred from V specific flags
	c_flags                 []string @[long: 'cflag'; short: c; xdoc: 'Additional flags for the C compiler']
	v_flags                 []string @[long: 'flag'; short: f; xdoc: 'Additional flags for the V compiler']
	lib_name                string   @[ignore] // Generated field depending on names in input/flags
	assets_extra            []string @[long: 'assets'; short: a; xdoc: 'Asset dir(s) to include in build']
	libs_extra              []string @[long: 'libs'; short: l; xdoc: 'Lib dir(s) to include in build']
	version_code            int      @[xdoc: 'Build version code (android:versionCode)']
	keystore                string   @[xdoc: 'Use this keystore file to sign the package']
	keystore_alias          string   @[xdoc: 'Use this keystore alias from the keystore file to sign the package']
	keystore_password       string   @[ignore] // Resolved at runtime via env var see: Options.resolve()
	keystore_alias_password string   @[ignore] // Resolved at runtime via env var see: Options.resolve()
	// Build specifics
	build_tools     string @[xdoc: 'Version of build-tools to use (--list-build-tools)']
	api_level       string @[long: 'api'; xdoc: 'Android API level to use (--list-apis)']
	ndk_version     string @[xdoc: 'Android NDK version to use (--list-ndks)']
	min_sdk_version int = android.default_min_sdk_version    @[xdoc: 'Minimum SDK version version code (android:minSdkVersion)']
	// Deployment
	device_id string   @[long: 'device'; short: d; xdoc: 'Deploy to device <id>. Use "auto" to use first available.']
	log_tags  []string @[long: 'log-tag'; xdoc: 'Additional tags to include in output when using --log']
}

// options_from_env returns an `Option` struct filled with flags set via
// the `VAB_FLAGS` env variable otherwise it returns a default `Option` struct.
pub fn options_from_env(defaults Options) !Options {
	env_vab_flags := os.getenv('VAB_FLAGS')
	$if vab_debug_options ? {
		eprintln('--- ${@FN} ---')
		dump(env_vab_flags)
	}
	if env_vab_flags != '' {
		mut vab_flags := [os.args[0]]
		vab_flags << string_to_args(env_vab_flags)!
		opts, _ := options_from_arguments(vab_flags, defaults)!
		return opts
	}
	return defaults
}

// options_from_dot_vab will return `Options` with any content
// found in any `.vab` config files.
pub fn options_from_dot_vab(input string, defaults Options) !Options {
	// Look up values in input .vab file next to input
	// NOTE: developers bear in mind that `input` is not guaranteed to be valid.
	dot_vab_file := dot_vab_path(input)
	dot_vab := if dot_vab_file != '' { os.read_file(dot_vab_file) or { '' } } else { '' }
	mut opts := defaults
	if dot_vab.len > 0 {
		if dot_vab.contains('icon:') {
			vab_icon := dot_vab.all_after('icon:').all_before('\n').replace("'", '').replace('"',
				'').trim(' ')
			if vab_icon != '' {
				$if vab_debug_options ? {
					println('Using icon "vab_icon" from .vab file "${dot_vab_file}"')
				}
				opts.icon = vab_icon
			}
		}
		if dot_vab.contains('app_name:') {
			vab_app_name := dot_vab.all_after('app_name:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_app_name != '' {
				$if vab_debug_options ? {
					println('Using app name "vab_app_name" from .vab file "${dot_vab_file}"')
				}
				opts.app_name = vab_app_name
			}
		}
		if dot_vab.contains('package_id:') {
			vab_package_id := dot_vab.all_after('package_id:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_package_id != '' {
				$if vab_debug_options ? {
					println('Using package id "${vab_package_id}" from .vab file "${dot_vab_file}"')
				}
				opts.package_id = vab_package_id
			}
		}

		if dot_vab.contains('min_sdk_version:') {
			vab_min_sdk_version := dot_vab.all_after('min_sdk_version:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_min_sdk_version != '' {
				$if vab_debug_options ? {
					println('Using minimum SDK version "${vab_min_sdk_version}" from .vab file "${dot_vab_file}"')
				}
				opts.min_sdk_version = vab_min_sdk_version.int()
			}
		}

		if dot_vab.contains('package_overrides:') {
			mut vab_package_overrides_path := dot_vab.all_after('package_overrides:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_package_overrides_path != '' {
				if vab_package_overrides_path in ['.', '..']
					|| vab_package_overrides_path.starts_with('.' + os.path_separator)
					|| vab_package_overrides_path.starts_with('..' + os.path_separator) {
					dot_vab_file_dir := os.dir(dot_vab_file)
					if vab_package_overrides_path == '.' {
						vab_package_overrides_path = dot_vab_file_dir
					} else if vab_package_overrides_path == '..' {
						vab_package_overrides_path = os.dir(dot_vab_file_dir)
					} else if vab_package_overrides_path.starts_with('.' + os.path_separator) {
						vab_package_overrides_path = vab_package_overrides_path.replace_once('.' +
							os.path_separator, dot_vab_file_dir + os.path_separator)
					} else {
						// vab_package_overrides_path.starts_with('..'+os.path_separator)
						vab_package_overrides_path = vab_package_overrides_path.replace_once('..' +
							os.path_separator, os.dir(dot_vab_file_dir) + os.path_separator)
					}
				}
				$if vab_debug_options ? {
					println('Using package overrides in "${vab_package_overrides_path}" from .vab file "${dot_vab_file}"')
				}
				opts.package_overrides_path = vab_package_overrides_path
			}
		}
		if dot_vab.contains('activity_name:') {
			vab_activity := dot_vab.all_after('activity_name:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_activity != '' {
				$if vab_debug_options ? {
					println('Using activity name "${vab_activity}" from .vab file "${dot_vab_file}"')
				}
				opts.activity_name = vab_activity
			}
		}
		if dot_vab.contains('assets_extra:') {
			vab_assets_extra := dot_vab.all_after('assets_extra:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if os.is_dir(vab_assets_extra) {
				$if vab_debug_options ? {
					println('Appending extra assets at "${vab_assets_extra}" from .vab file "${dot_vab_file}"')
				}
				opts.assets_extra << vab_assets_extra
			}
		}
		if dot_vab.contains('libs_extra:') {
			vab_libs_extra := dot_vab.all_after('libs_extra:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if os.is_dir(vab_libs_extra) {
				$if vab_debug_options ? {
					println('Appending extra libs at "${vab_libs_extra}" from .vab file "${dot_vab_file}"')
				}
				opts.libs_extra << vab_libs_extra
			}
		}
	}
	return opts
}

// options_from_arguments returns an `Option` merged from (CLI/Shell -style) `arguments` using `defaults` as
// values where no value can be matched in `arguments`.
pub fn options_from_arguments(arguments []string, defaults Options) !(Options, []string) {
	mut args := arguments.clone()
	mut v_flags := []string{}
	mut cmd_args := []string{}

	// Indentify special V args in args that `vab` supports and remove them
	// from the input args so they do not cause flag parsing errors below
	for special_arg in special_v_args {
		if special_arg in args {
			if special_arg == '-gc' {
				gc_type := args[(args.index(special_arg)) + 1]
				if gc_type.starts_with('-') {
					return error('flag `-gc` requires an non-flag argument')
				}
				v_flags << special_arg + ' ${gc_type}'
				args.delete(args.index(special_arg) + 1)
			} else if special_arg.starts_with('-') {
				v_flags << special_arg
			} else {
				cmd_args << special_arg
			}
			args.delete(args.index(special_arg))
		}
	}

	// Handle sub-commands and a few oddities that `vab` has supported historically
	mut verbosity := defaults.verbosity
	mut archs := defaults.archs.clone()
	mut run_builtin_cmd := defaults.run_builtin_cmd

	for i := 0; i < args.len; i++ {
		arg := args[i]
		if i <= 1 && arg in subcmds_builtin {
			// rip built in sub-commands at the start of the args array
			run_builtin_cmd = arg
			args.delete(i)
		} else if arg in ['-v', '--verbosity'] {
			// legacy support for `vab -v` (-v *without* an interger)
			verbosity_arg := args[i + 1] or { '' }
			if verbosity_arg.starts_with('-') {
				verbosity = 1
			} else if verbosity_arg != '' {
				verbosity = verbosity_arg.int()
				args.delete(i + 1)
			}
			args.delete(i)
		} else if arg == '--archs' {
			// rip, validate and convert e.g. 'arm64-v8a, armeabi-v7a,x86' to ['arm64-v8a', 'armeabi-v7a', 'x86']
			archs_value := args[i + 1] or { '' }
			if archs_value == '' {
				return error('flag `--archs` requires an argument')
			} else if archs_value.starts_with('-') {
				return error('flag `--archs` requires an non-flag argument')
			}
			archs = archs_value.split(',').map(it.trim_space())
			args.delete(i + 1)
			args.delete(i)
		}
	}

	// Validate archs
	for arch in archs {
		if arch !in ndk.supported_archs {
			return error('arch "${arch}" is not a supported Android CPU architecture')
		}
	}

	options, unmatched := flag.using[Options](defaults, args, skip: 1, style: .v_flag_parser)!

	mut c_flags := options.c_flags.clone()
	for c_flag in defaults.c_flags {
		if c_flag !in c_flags {
			c_flags << c_flag
		}
	}

	v_flags << options.v_flags
	for v_flag in defaults.v_flags {
		if v_flag !in v_flags {
			v_flags << v_flag
		}
	}

	mut log_tags := options.log_tags.clone()
	for log_tag in defaults.log_tags {
		if log_tag !in log_tags {
			log_tags << log_tag
		}
	}

	mut additional_args := options.additional_args.clone()
	for additional_arg in defaults.additional_args {
		if additional_arg !in additional_args {
			additional_args << additional_arg
		}
	}
	for additional_arg in unmatched {
		if additional_arg !in additional_args {
			additional_args << additional_arg
		}
	}

	opt := Options{
		...options
		run:             'run' in cmd_args
		run_builtin_cmd: run_builtin_cmd
		archs:           archs
		v_flags:         v_flags
		c_flags:         c_flags
		verbosity:       verbosity
		log_tags:        log_tags
		additional_args: additional_args
	}

	$if vab_debug_options ? {
		eprintln('--- ${@FN} ---')
		dump(arguments)
		dump(v_flags)
		dump(archs)
		dump(cmd_args)
		dump(unmatched)
		dump(args)
		dump(opt)
	}

	return opt, unmatched
}

// extend_from_dot_vab will merge the `Options` with any content
// found in any `.vab` config files.
@[deprecated: 'use options_from_dot_vab instead']
pub fn (mut opt Options) extend_from_dot_vab() {
	// Look up values in input .vab file next to input if no flags or defaults was set
	dot_vab_file := dot_vab_path(opt.input)
	dot_vab := os.read_file(dot_vab_file) or { '' }
	if dot_vab.len > 0 {
		if opt.icon == '' && dot_vab.contains('icon:') {
			vab_icon := dot_vab.all_after('icon:').all_before('\n').replace("'", '').replace('"',
				'').trim(' ')
			if vab_icon != '' {
				if opt.verbosity > 1 {
					println('Using icon "vab_icon" from .vab file "${dot_vab_file}"')
				}
				opt.icon = vab_icon
			}
		}
		if opt.app_name == android.default_app_name && dot_vab.contains('app_name:') {
			vab_app_name := dot_vab.all_after('app_name:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_app_name != '' {
				if opt.verbosity > 1 {
					println('Using app name "vab_app_name" from .vab file "${dot_vab_file}"')
				}
				opt.app_name = vab_app_name
			}
		}
		if opt.package_id == android.default_package_id && dot_vab.contains('package_id:') {
			vab_package_id := dot_vab.all_after('package_id:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_package_id != '' {
				if opt.verbosity > 1 {
					println('Using package id "${vab_package_id}" from .vab file "${dot_vab_file}"')
				}
				opt.package_id = vab_package_id
			}
		}
		if opt.min_sdk_version == android.default_min_sdk_version
			&& dot_vab.contains('min_sdk_version:') {
			vab_min_sdk_version := dot_vab.all_after('min_sdk_version:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_min_sdk_version != '' {
				if opt.verbosity > 1 {
					println('Using minimum SDK version "${vab_min_sdk_version}" from .vab file "${dot_vab_file}"')
				}
				opt.min_sdk_version = vab_min_sdk_version.int()
			}
		}
		if opt.package_overrides_path == '' && dot_vab.contains('package_overrides:') {
			mut vab_package_overrides_path := dot_vab.all_after('package_overrides:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_package_overrides_path != '' {
				if vab_package_overrides_path in ['.', '..']
					|| vab_package_overrides_path.starts_with('.' + os.path_separator)
					|| vab_package_overrides_path.starts_with('..' + os.path_separator) {
					dot_vab_file_dir := os.dir(dot_vab_file)
					if vab_package_overrides_path == '.' {
						vab_package_overrides_path = dot_vab_file_dir
					} else if vab_package_overrides_path == '..' {
						vab_package_overrides_path = os.dir(dot_vab_file_dir)
					} else if vab_package_overrides_path.starts_with('.' + os.path_separator) {
						vab_package_overrides_path = vab_package_overrides_path.replace_once('.' +
							os.path_separator, dot_vab_file_dir + os.path_separator)
					} else {
						// vab_package_overrides_path.starts_with('..'+os.path_separator)
						vab_package_overrides_path = vab_package_overrides_path.replace_once('..' +
							os.path_separator, os.dir(dot_vab_file_dir) + os.path_separator)
					}
				}
				if opt.verbosity > 1 {
					println('Using package overrides in "${vab_package_overrides_path}" from .vab file "${dot_vab_file}"')
				}
				opt.package_overrides_path = vab_package_overrides_path
			}
		}
		if opt.activity_name == '' && dot_vab.contains('activity_name:') {
			vab_activity := dot_vab.all_after('activity_name:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if vab_activity != '' {
				if opt.verbosity > 1 {
					println('Using activity name "${vab_activity}" from .vab file "${dot_vab_file}"')
				}
				opt.activity_name = vab_activity
			}
		}
		if dot_vab.contains('assets_extra:') {
			vab_assets_extra := dot_vab.all_after('assets_extra:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if os.is_dir(vab_assets_extra) {
				if opt.verbosity > 1 {
					println('Appending extra assets at "${vab_assets_extra}" from .vab file "${dot_vab_file}"')
				}
				opt.assets_extra << vab_assets_extra
			}
		}
		if dot_vab.contains('libs_extra:') {
			vab_libs_extra := dot_vab.all_after('libs_extra:').all_before('\n').replace("'",
				'').replace('"', '').trim(' ')
			if os.is_dir(vab_libs_extra) {
				if opt.verbosity > 1 {
					println('Appending extra libs at "${vab_libs_extra}" from .vab file "${dot_vab_file}"')
				}
				opt.libs_extra << vab_libs_extra
			}
		}
	}
}

// ensure_launch_fields sets `package_id` and `activity_name` fields if they're blank
// these fields are necessary for succesful deployment.
pub fn (mut opt Options) ensure_launch_fields() {
	// If no package id or activity name has set, use the defaults
	if opt.package_id == '' {
		opt.package_id = android.default_package_id
	}
	if opt.activity_name == '' {
		opt.activity_name = android.default_activity_name
	}
}

// validate_env ensures that `Optins` meet all runtime requrements.
pub fn (opt &Options) validate_env() {
	// Validate JDK
	jdk_version := java.jdk_version()
	if jdk_version == '' {
		eprintln('No Java JDK install(s) could be detected')
		eprintln('Please install Java JDK >= 8 or provide a valid path via JAVA_HOME')
		exit(1)
	}

	jdk_semantic_version := semver.from(jdk_version) or {
		panic(@MOD + '.' + @FN + ':' + @LINE +
			' error converting jdk_version "${jdk_version}" to semantic version.\nsemver: ${err}')
	}
	if !(jdk_semantic_version >= semver.build(1, 8, 0)) { // NOTE When did this break:.satisfies('1.8.*') ???
		// Some Android tools like `sdkmanager` in cmdline-tools;1.0 only worked with Java 8 JDK (1.8.x).
		// (Absolute mess, yes)
		eprintln('Java JDK version ${jdk_version} is not supported')
		eprintln('Please install Java JDK >= 8 or provide a valid path via JAVA_HOME')
		exit(1)
	}

	// Validate build-tools
	if sdk.default_build_tools_version == '' {
		eprintln('No known Android build-tools version(s) could be detected in the SDK.')
		eprintln('(A vab compatible version can be installed with `${exe_short_name} install "build-tools;${sdk.min_supported_build_tools_version}"`)')
		exit(1)
	} else if semver.is_valid(sdk.default_build_tools_version) {
		build_tools_semantic_version := semver.from(sdk.default_build_tools_version) or {
			panic(@MOD + '.' + @FN + ':' + @LINE +
				' error converting build-tools version "${sdk.default_build_tools_version}" to semantic version.\nsemver: ${err}')
		}

		if !build_tools_semantic_version.satisfies('>=${sdk.min_supported_build_tools_version}') {
			// Some Android tools we need like `apksigner` is currently only available with build-tools >= 24.0.3.
			// (Absolute mess, yes)
			eprintln('Android build-tools version "${sdk.default_build_tools_version}" is not supported by ${exe_short_name}.')
			eprintln('Please install a build-tools version >= ${sdk.min_supported_build_tools_version} (run `${exe_short_name} install build-tools` to install the default version).')
			eprintln('You can see available build-tools with `${exe_short_name} --list-build-tools`.')
			eprintln('To use a specific version you can use `${exe_short_name} --build-tools "<version>"`.')
			exit(1)
		}
	} else {
		// Not blank but not a recognized format (x.y.z)
		// NOTE It *might* be a SDK managed by the system package manager (apt, pacman etc.) - so we warn about it and go on...
		eprintln('Notice: Android build-tools version "${sdk.default_build_tools_version}" is unknown to ${exe_short_name}, things might not work as expected.')
	}

	// Validate Android NDK requirements
	if ndk.found() {
		// The NDK version is sniffed from the directory it resides in (which can be anything)
		// So we only report back if the verion can be read
		if ndk_semantic_version := semver.from(opt.ndk_version) {
			if ndk_semantic_version < semver.build(21, 1, 0) {
				eprintln('Android NDK >= 21.1.x is currently needed. "${opt.ndk_version}" is too low.')
				eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
				eprintln('or run `${exe_short_name} install "ndk;<version>"`')
				exit(1)
			}
		} else {
			eprintln('Notice: Android NDK version could not be validated from "${opt.ndk_version}"')
			eprintln('Notice: The NDK is not guaranteed to be compatible with ${exe_short_name}')
		}
	}

	// API level
	if opt.api_level.i16() < sdk.default_api_level.i16() {
		eprintln('Notice: Android API level ${opt.api_level} is less than the default level (${sdk.default_api_level}).')
	}
	// AAB format
	has_bundletool := env.has_bundletool()
	has_aapt2 := env.has_aapt2()
	if opt.package_format == 'aab' && !(has_bundletool && has_aapt2) {
		if !has_bundletool {
			eprintln('The tool `bundletool` is needed for AAB package building and deployment.')
			eprintln('Please install bundletool manually and provide a path to it via BUNDLETOOL')
			eprintln('or run `${exe_short_name} install bundletool`')
		}
		if !has_aapt2 {
			eprintln('The tool `aapt2` is needed for AAB package building.')
			eprintln('Please install aapt2 manually and provide a path to it via AAPT2')
			eprintln('or run `${exe_short_name} install aapt2`')
		}
		exit(1)
	}
}

// resolve_output modifies `Options.output` according to what `Option.input` contains.
pub fn (mut opt Options) resolve_output() {
	// Resolve output
	mut output_file := ''
	input_file_ext := os.file_ext(opt.input).trim_left('.')
	output_file_ext := os.file_ext(opt.output).trim_left('.')
	// Infer from input, if a package file: vab <input package file>
	if input_file_ext in ['apk', 'aab'] {
		output_file = opt.input
		opt.package_format = input_file_ext // apk / aab
	} else if output_file_ext in ['apk', 'aab'] { // Infer from output, if a package file: vab -o <output package file> <input path>
		output_file = opt.output
		opt.package_format = output_file_ext // apk / aab
	} else { // Generate from defaults: vab [-o <output>] <input>
		default_file_name := opt.app_name.replace(os.path_separator.str(), '').replace(' ',
			'_').to_lower()
		if opt.output != '' {
			ext := os.file_ext(opt.output)
			if ext != '' {
				output_file = opt.output.all_before(ext)
			} else {
				output_file = os.join_path(opt.output.trim_right(os.path_separator), default_file_name)
			}
		} else {
			output_file = default_file_name
		}
		if opt.package_format == 'aab' {
			output_file += '.aab'
		} else {
			output_file += '.apk'
		}
	}
	opt.output = output_file
}

// resolve tries to resolve `Options` in a balance so everything works
// optimally weighted against the best user experience.
pub fn (mut opt Options) resolve(exit_on_error bool) {
	// Validate SDK API level
	mut api_level := sdk.default_api_level
	if api_level == '' {
		eprintln('No Android API levels could be detected in the SDK.')
		eprintln('If the SDK is working and writable, new platforms can be installed with:')
		eprintln('`${exe_short_name} install "platforms;android-<API LEVEL>"`')
		eprintln('You can set a custom SDK with the ANDROID_SDK_ROOT env variable')
		if exit_on_error {
			exit(1)
		}
	}
	if opt.api_level != '' {
		// Set user requested API level
		if sdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			eprintln('Notice: The requested Android API level "${opt.api_level}" is not available in the SDK.')
			eprintln('Notice: Falling back to default "${api_level}"')
		}
	}
	if api_level.i16() < sdk.min_supported_api_level.i16() {
		eprintln('Android API level "${api_level}" is less than the supported level (${sdk.min_supported_api_level}).')
		eprintln('A vab compatible version can be installed with `${exe_short_name} install "platforms;android-${sdk.min_supported_api_level}"`')
		if exit_on_error {
			exit(1)
		}
	}

	opt.api_level = api_level

	// Validate build-tools version
	mut build_tools_version := sdk.default_build_tools_version
	if opt.build_tools != '' {
		if sdk.has_build_tools(opt.build_tools) {
			build_tools_version = opt.build_tools
		} else {
			// TODO FIX Warnings
			eprintln('Android build-tools version "${opt.build_tools}" is not available in SDK.')
			eprintln('(It can be installed with `${exe_short_name} install "build-tools;${opt.build_tools}"`)')
			eprintln('Falling back to default ${build_tools_version}')
		}
	}
	if build_tools_version == '' {
		eprintln('No known Android build-tools version(s) could be detected in the SDK.')
		eprintln('(A vab compatible version can be installed with `${exe_short_name} install "build-tools;${sdk.min_supported_build_tools_version}"`)')
		if exit_on_error {
			exit(1)
		}
	}

	opt.build_tools = build_tools_version

	// Validate NDK version
	mut ndk_version := ndk.default_version()
	if ndk_version == '' {
		eprintln('No Android NDK versions could be detected.')
		eprintln('If the SDK is working and writable, new NDK versions can be installed with:')
		eprintln('`${exe_short_name} install "ndk;<NDK VERSION>"`')
		eprintln('The minimum supported NDK version is "${ndk.min_supported_version}"')
		if exit_on_error {
			exit(1)
		}
	}
	if opt.ndk_version != '' {
		// Set user requested NDK version
		if ndk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android NDK version "${opt.ndk_version}" could not be found.')
			eprintln('If the SDK is working and writable, new NDK versions can be installed with:')
			eprintln('`${exe_short_name} install "ndk;<NDK VERSION>"`')
			eprintln('The minimum supported NDK version is "${ndk.min_supported_version}"')
			eprintln('Falling back to default ${ndk_version}')
		}
	}

	opt.ndk_version = ndk_version

	// Resolve NDK vs. SDK available platforms
	min_ndk_api_level := ndk.min_api_available(opt.ndk_version)
	max_ndk_api_level := ndk.max_api_available(opt.ndk_version)
	if opt.api_level.i16() > max_ndk_api_level.i16()
		|| opt.api_level.i16() < min_ndk_api_level.i16() {
		if opt.api_level.i16() > max_ndk_api_level.i16() {
			eprintln('Notice: Falling back to API level "${max_ndk_api_level}" (SDK API level ${opt.api_level} > highest NDK API level ${max_ndk_api_level}).')
			opt.api_level = max_ndk_api_level
		}
		if opt.api_level.i16() < min_ndk_api_level.i16() {
			if sdk.has_api(min_ndk_api_level) {
				eprintln('Notice: Falling back to API level "${min_ndk_api_level}" (SDK API level ${opt.api_level} < lowest NDK API level ${max_ndk_api_level}).')
				opt.api_level = min_ndk_api_level
			}
		}
	}

	// Java package ids/names are integrated hard into the eco-system
	opt.lib_name = opt.app_name.replace(' ', '_').to_lower()

	// Convert v flags captured to option field
	if '-prod' in opt.v_flags {
		opt.is_prod = true
		opt.v_flags.delete(opt.v_flags.index('-prod'))
	}

	if os.getenv('KEYSTORE_PASSWORD') != '' {
		opt.keystore_password = os.getenv('KEYSTORE_PASSWORD')
	}
	if os.getenv('KEYSTORE_ALIAS_PASSWORD') != '' {
		opt.keystore_alias_password = os.getenv('KEYSTORE_ALIAS_PASSWORD')
	}

	mut archs := opt.archs.map(it.trim_space()).filter(it != '')
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
		if opt.verbosity > 1 {
			eprintln('Setting all architectures: ${archs}')
		}
		opt.archs = archs
	}

	// If no device id has been set at this point,
	// check for ENV vars
	mut device_id := opt.device_id
	if device_id == '' {
		device_id = os.getenv('ANDROID_SERIAL')
		if device_id != '' {
			if opt.verbosity > 1 {
				eprintln('Using device "${device_id}" from ANDROID_SERIAL env variable')
			}
			opt.device_id = device_id
		}
	}
}

// resolve_keystore returns an `android.Keystore` resolved from `Options`.
pub fn (opt &Options) resolve_keystore() !android.Keystore {
	mut keystore := android.Keystore{
		path:           opt.keystore
		password:       opt.keystore_password
		alias:          opt.keystore_alias
		alias_password: opt.keystore_alias_password
	}
	if !os.is_file(keystore.path) {
		if keystore.path != '' {
			eprintln('Keystore "${keystore.path}" is not a valid file')
			eprintln('Notice: Signing with debug keystore')
		}
		keystore = android.default_keystore(cache_directory)!
	} else {
		keystore = android.resolve_keystore(keystore)!
	}
	return keystore
}

// as_android_deploy_options returns `android.DeployOptions` based on the fields in `Options`.
pub fn (opt &Options) as_android_deploy_options() !android.DeployOptions {
	mut run := ''
	if opt.run {
		package_id := opt.package_id
		activity_name := opt.activity_name
		run = '${package_id}/${package_id}.${activity_name}'
		if opt.verbosity > 1 {
			println('Should run "${package_id}/${package_id}.${activity_name}"')
		}
	}

	mut log_tags := opt.log_tags.clone()
	log_tags << opt.lib_name

	// Package format apk/aab
	format := match opt.package_format {
		'aab' {
			android.PackageFormat.aab
		}
		else {
			android.PackageFormat.apk
		}
	}

	deploy_opt := android.DeployOptions{
		verbosity: opt.verbosity
		format:    format
		// keystore: keystore
		activity_name:    opt.activity_name
		work_dir:         opt.work_dir
		v_flags:          opt.v_flags
		device_id:        opt.device_id
		deploy_file:      opt.output
		kill_adb:         os.getenv('VAB_KILL_ADB') != ''
		clear_device_log: opt.clear_device_log
		device_log:       opt.device_log || opt.device_log_raw
		log_mode:         if opt.device_log_raw {
			android.LogMode.raw
		} else {
			android.LogMode.filtered
		}
		log_tags: log_tags
		run:      run
	}

	return deploy_opt
}

// as_android_compile_options returns `android.CompileOptions` based on the fields in `Options`.
pub fn (opt &Options) as_android_compile_options() android.CompileOptions {
	comp_opt := android.CompileOptions{
		verbosity:       opt.verbosity
		cache:           opt.cache
		parallel:        opt.parallel
		is_prod:         opt.is_prod
		gles_version:    opt.gles_version
		v_flags:         opt.v_flags
		c_flags:         opt.c_flags
		archs:           opt.archs
		work_dir:        opt.work_dir
		input:           opt.input
		ndk_version:     opt.ndk_version
		lib_name:        opt.lib_name
		api_level:       opt.api_level
		min_sdk_version: opt.min_sdk_version
	}
	return comp_opt
}

// as_android_package_options returns `android.PackageOptions` based on the fields in `Options`.
pub fn (opt &Options) as_android_package_options() android.PackageOptions {
	// Package format apk/aab
	format := match opt.package_format {
		'aab' {
			android.PackageFormat.aab
		}
		else {
			android.PackageFormat.apk
		}
	}

	pck_opt := android.PackageOptions{
		verbosity:       opt.verbosity
		work_dir:        opt.work_dir
		is_prod:         opt.is_prod
		api_level:       opt.api_level
		min_sdk_version: opt.min_sdk_version
		gles_version:    opt.gles_version
		build_tools:     opt.build_tools
		app_name:        opt.app_name
		lib_name:        opt.lib_name
		package_id:      opt.package_id
		format:          format
		activity_name:   opt.activity_name
		icon:            opt.icon
		version_code:    opt.version_code
		v_flags:         opt.v_flags
		input:           opt.input
		assets_extra:    opt.assets_extra
		libs_extra:      opt.libs_extra
		output_file:     opt.output
		overrides_path:  opt.package_overrides_path
	}
	return pck_opt
}

// as_android_screenshot_options returns `android.ScreenshotOptions` based on the fields in `Options`.
pub fn (opt &Options) as_android_screenshot_options(deploy_opts android.DeployOptions) android.ScreenshotOptions {
	screenshot_opt := android.ScreenshotOptions{
		deploy_options: deploy_opts
		path:           opt.screenshot
		delay:          opt.screenshot_delay
		on_log:         opt.screenshot_on_log
		on_log_timeout: opt.screenshot_on_log_timeout
	}
	return screenshot_opt
}
