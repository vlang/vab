// Copyright(C) 2019-2021 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module main

import os
import flag
import semver
import vxt
import java
import android
import android.sdk
import android.ndk
import android.env

const (
	exe_version          = version()
	exe_name             = os.file_name(os.executable())
	exe_dir              = os.dir(os.real_path(os.executable()))
	exe_git_hash         = vab_commit_hash()
	rip_vflags           = ['-autofree', '-gc', '-g', '-cg', '-prod', 'run']
	subcmds              = ['test-cleancode']
	accepted_input_files = ['.v', '.apk', '.aab']
)

struct Options {
	// Internals
	verbosity int
	work_dir  string
	// Build, packaging and deployment
	cache          bool
	version_code   int
	device_id      string
	keystore       string
	keystore_alias string
	// Build specifics
	gles_version     int
	c_flags          []string // flags passed to the C compiler(s)
	no_printf_hijack bool     // Do not let V redefine printf for log output aka. V_ANDROID_LOG_PRINT
	archs            []string
	// Deploy specifics
	run            bool
	device_log     bool
	device_log_raw bool
	// Detected environment
	dump_usage       bool
	list_ndks        bool
	list_apis        bool
	list_build_tools bool
mut:
	input  string
	output string
	// App essentials
	app_name               string
	icon                   string
	package_id             string
	activity_name          string
	package_format         string
	package_overrides_path string
	// Build and packaging
	is_prod                 bool
	v_flags                 []string // flags passed to the V compiler
	lib_name                string
	assets_extra            []string
	keystore_password       string
	keystore_alias_password string
	// Build specifics
	build_tools string
	api_level   string
	ndk_version string
}

fn main() {
	mut args := os.args.clone()

	// Indentify sub-commands.
	for subcmd in subcmds {
		if subcmd in args {
			// First encountered known sub-command is executed on the spot.
			exit(launch_cmd(args[args.index(subcmd)..]))
		}
	}

	mut v_flags := []string{}
	mut cmd_flags := []string{}
	// Indentify special flags in args before FlagParser ruin them.
	// E.g. the -autofree flag will result in dump_usage being called for some weird reason???
	for special_flag in rip_vflags {
		if special_flag in args {
			if special_flag == '-gc' {
				gc_type := args[(args.index(special_flag)) + 1]
				v_flags << special_flag + ' $gc_type'
				args.delete(args.index(special_flag) + 1)
			} else if special_flag.starts_with('-') {
				v_flags << special_flag
			} else {
				cmd_flags << special_flag
			}
			args.delete(args.index(special_flag))
		}
	}

	mut fp := flag.new_flag_parser(args)
	fp.application(exe_name)
	fp.version('0.2.0')
	fp.description('V Android Bootstrapper.\nCompile, package and deploy graphical V apps for Android.')
	fp.arguments_description('input')

	fp.skip_executable()

	mut verbosity := fp.int_opt('verbosity', `v`, 'Verbosity level 1-3') or { 0 }
	// TODO implement FlagParser 'is_sat(name string) bool' or something in vlib for this usecase?
	if ('-v' in os.args || 'verbosity' in os.args) && verbosity == 0 {
		verbosity = 1
	}

	mut opt := Options{
		assets_extra: fp.string_multi('assets', `a`, 'Asset dir(s) to include in build')
		v_flags: fp.string_multi('flag', `f`, 'Additional flags for the V compiler')
		//
		no_printf_hijack: fp.bool('no-printf-hijack', 0, false, 'Do not let V redefine printf for log output (aka. do not define V_ANDROID_LOG_PRINT)')
		c_flags: fp.string_multi('cflag', `c`, 'Additional flags for the C compiler')
		archs: fp.string('archs', 0, '', 'Comma separated string with any of $android.default_archs').split(',')
		gles_version: fp.int('gles', 0, android.default_gles_version, 'GLES version to use from any of $android.supported_gles_versions')
		//
		device_id: fp.string('device', `d`, '', 'Deploy to device <id>. Use "auto" to use first available.')
		run: 'run' in cmd_flags // fp.bool('run', `r`, false, 'Run the app on the device after successful deployment.')
		device_log: fp.bool('log', 0, false, 'Enable device logging after deployment.')
		device_log_raw: fp.bool('log-raw', 0, false, 'Enable unfiltered, full device logging after deployment.')
		//
		keystore: fp.string('keystore', 0, '', 'Use this keystore file to sign the package')
		keystore_alias: fp.string('keystore-alias', 0, '', 'Use this keystore alias from the keystore file to sign the package')
		//
		dump_usage: fp.bool('help', `h`, false, 'Show this help message and exit')
		cache: !fp.bool('nocache', 0, false, 'Do not use build cache')
		//
		app_name: fp.string('name', 0, android.default_app_name, 'Pretty app name')
		package_id: fp.string('package-id', 0, android.default_package_id, 'App package ID (e.g. "org.company.app")')
		package_overrides_path: fp.string('package-overrides', 0, '', 'Package file overrides path (e.g. "/tmp/java")')
		package_format: fp.string('package', `p`, android.default_package_format, 'App package format. Any of $android.supported_package_formats')
		activity_name: fp.string('activity-name', 0, '', 'The name of the main activity (e.g. "VActivity")')
		icon: fp.string('icon', 0, '', 'App icon')
		version_code: fp.int('version-code', 0, 0, 'Build version code (android:versionCode)')
		//
		output: fp.string('output', `o`, '', 'Path to output (dir/file)')
		//
		verbosity: verbosity
		//
		build_tools: fp.string('build-tools', 0, '', 'Version of build-tools to use (--list-build-tools)')
		api_level: fp.string('api', 0, '', 'Android API level to use (--list-apis)')
		//
		ndk_version: fp.string('ndk-version', 0, '', 'Android NDK version to use (--list-ndks)')
		//
		work_dir: os.join_path(os.temp_dir(), exe_name.replace(' ', '_').to_lower())
		//
		list_ndks: fp.bool('list-ndks', 0, false, 'List available NDK versions')
		list_apis: fp.bool('list-apis', 0, false, 'List available API levels')
		list_build_tools: fp.bool('list-build-tools', 0, false, 'List available Build-tools versions')
	}

	additional_args := fp.finalize() or {
		println(fp.usage())
		eprintln(err)
		exit(1)
	}

	if opt.dump_usage {
		println(fp.usage())
		exit(0)
	}

	if opt.list_ndks {
		if !ndk.found() {
			eprintln('No NDK could be found. Please use `$exe_name doctor` to get more information.')
			exit(1)
		}
		for ndk_v in ndk.versions_available() {
			println(ndk_v)
		}
		exit(0)
	}

	if opt.list_apis {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `$exe_name doctor` to get more information.')
			exit(1)
		}
		for api in sdk.apis_available() {
			println(api)
		}
		exit(0)
	}

	if opt.list_build_tools {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `$exe_name doctor` to get more information.')
			exit(1)
		}
		for btv in sdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}
	// All flags after this requires an input argument
	if fp.args.len == 0 {
		println(fp.usage())
		eprintln('No arguments given')
		exit(1)
	}

	if additional_args.len > 1 {
		if additional_args[0] == 'install' {
			install_arg := additional_args[1]
			res := env.install(install_arg, opt.verbosity)
			if res == 0 && opt.verbosity > 0 {
				if install_arg != 'auto' {
					println('Installed $install_arg successfully.')
				} else {
					println('Installed all dependencies successfully.')
				}
			}
			exit(res)
		}
	}

	// Merge v flags captured before FlagParser
	v_flags << opt.v_flags
	if '-prod' in v_flags {
		opt.is_prod = true
		v_flags.delete(v_flags.index('-prod'))
	}
	opt.v_flags = v_flags

	// Call the doctor at this point
	if additional_args.len > 0 {
		if additional_args[0] == 'doctor' {
			// Validate environment
			check_essentials(false)
			resolve_options(mut opt, false)
			doctor(opt)
			exit(0)
		}
	}
	// Validate environment
	check_essentials(true)
	resolve_options(mut opt, true)

	input := fp.args[fp.args.len - 1]

	input_ext := os.file_ext(input)

	if !(os.is_dir(input) || input_ext in accepted_input_files) {
		println(fp.usage())
		eprintln('$exe_name requires input to be a V file, an APK, AAB or a directory containing V sources')
		exit(1)
	}
	opt.input = input

	extend_options_from_dot_vab(mut opt)

	kill_adb := os.getenv('VAB_KILL_ADB') != ''

	// Validate environment after options and input has been resolved
	validate_env(opt)

	mut run := ''
	mut package_id := opt.package_id
	mut activity_name := opt.activity_name
	if opt.run {
		if package_id == '' {
			package_id = android.default_package_id
		}
		if activity_name == '' {
			activity_name = android.default_activity_name
		}
		run = '$package_id/${package_id}.$activity_name'
		if opt.verbosity > 1 {
			println('Should run "$package_id/${package_id}.$activity_name"')
		}
	}

	mut device_id := opt.device_id
	if device_id == '' {
		device_id = os.getenv('ANDROID_SERIAL')
		if opt.verbosity > 1 && device_id != '' {
			println('Using device "$device_id" from ANDROID_SERIAL env')
		}
	}
	// Package format apk/aab
	format := match opt.package_format {
		'aab' {
			android.PackageFormat.aab
		}
		else {
			android.PackageFormat.apk
		}
	}

	// Keystore file
	mut keystore := android.Keystore{opt.keystore, opt.keystore_alias, opt.keystore_password, opt.keystore_alias_password}
	if !os.is_file(keystore.path) {
		if keystore.path != '' {
			println('Couldn\'t locate "$keystore.path"')
		}
		keystore.path = ''
	}
	if keystore.path == '' {
		keystore.path = os.join_path(exe_dir, 'debug.keystore')
	}
	keystore = android.resolve_keystore(keystore, opt.verbosity)

	log_tag := opt.lib_name
	deploy_opt := android.DeployOptions{
		verbosity: opt.verbosity
		format: format
		keystore: keystore
		activity_name: activity_name
		work_dir: opt.work_dir
		v_flags: opt.v_flags
		device_id: device_id
		deploy_file: opt.output
		kill_adb: kill_adb
		device_log: opt.device_log || opt.device_log_raw
		log_mode: if opt.device_log_raw { android.LogMode.raw } else { android.LogMode.filtered }
		log_tag: log_tag
		run: run
	}

	// Early deployment
	if input_ext in ['.apk', '.aab'] {
		if opt.device_id != '' {
			if !android.deploy(deploy_opt) {
				eprintln('$exe_name deployment didn\'t succeed')
				exit(1)
			} else {
				if opt.verbosity > 0 {
					println('Deployed to $opt.device_id successfully')
				}
				exit(0)
			}
		}
	}

	compile_cache_key := if os.is_dir(input) || input_ext == '.v' { opt.input } else { '' }
	comp_opt := android.CompileOptions{
		verbosity: opt.verbosity
		cache: opt.cache
		cache_key: compile_cache_key
		is_prod: opt.is_prod
		gles_version: opt.gles_version
		no_printf_hijack: opt.no_printf_hijack
		v_flags: opt.v_flags
		c_flags: opt.c_flags
		archs: opt.archs.filter(it.trim(' ') != '')
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		lib_name: opt.lib_name
		api_level: opt.api_level
	}
	if !android.compile(comp_opt) {
		eprintln('$exe_name compiling didn\'t succeed')
		exit(1)
	}

	pck_opt := android.PackageOptions{
		verbosity: opt.verbosity
		work_dir: opt.work_dir
		is_prod: opt.is_prod
		api_level: opt.api_level
		build_tools: opt.build_tools
		app_name: opt.app_name
		lib_name: opt.lib_name
		package_id: package_id
		format: format
		activity_name: activity_name
		icon: opt.icon
		version_code: opt.version_code
		v_flags: opt.v_flags
		input: opt.input
		assets_extra: opt.assets_extra
		output_file: opt.output
		keystore: keystore
		base_files: os.join_path(exe_dir, 'platforms', 'android')
		overrides_path: opt.package_overrides_path
	}
	if !android.package(pck_opt) {
		eprintln("Packaging didn't succeed")
		exit(1)
	}

	if device_id != '' {
		if !android.deploy(deploy_opt) {
			eprintln("Deployment didn't succeed")
			exit(1)
		} else {
			if opt.verbosity > 0 {
				println('Deployed to device ($device_id) successfully')
			}
		}
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `$exe_name --device <id> ${os.real_path(opt.output)}` to deploy package')
		}
	}
}

fn check_essentials(exit_on_error bool) {
	// Validate V install
	if vxt.vexe() == '' {
		eprintln('No V install could be detected')
		eprintln('Please install V from https://github.com/vlang/v')
		eprintln('or provide a valid path to V via VEXE env variable')
		if exit_on_error {
			exit(1)
		}
	}
	// Validate Java requirements
	if !java.jdk_found() {
		eprintln('No Java install(s) could be detected')
		eprintln('Please install Java JDK >= 8 or provide a valid path via JAVA_HOME')
		if exit_on_error {
			exit(1)
		}
	}
	// Validate Android SDK requirements
	if !sdk.found() {
		eprintln('No Android SDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `$exe_name install auto`')
		if exit_on_error {
			exit(1)
		}
	}
	// Validate Android NDK requirements
	if !ndk.found() {
		eprintln('No Android NDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
		eprintln('or run `$exe_name install ndk`')
		if exit_on_error {
			exit(1)
		}
	}
}

fn validate_env(opt Options) {
	// Validate JDK
	jdk_version := java.jdk_version()
	if jdk_version == '' {
		eprintln('No Java JDK install(s) could be detected')
		eprintln('Please install Java >= 8 JDK or provide a valid path via JAVA_HOME')
		exit(1)
	}

	jdk_semantic_version := semver.from(jdk_version) or {
		panic(@MOD + '.' + @FN + ':' + @LINE +
			' error converting jdk_version "$jdk_version" to semantic version.\nsemver: $err')
	}
	if !jdk_semantic_version.ge(semver.build(1, 8, 0)) { // NOTE When did this break:.satisfies('1.8.*') ???
		// Some Android tools like `sdkmanager` in cmdline-tools;1.0 only worked with Java 8 JDK (1.8.x).
		// (Absolute mess, yes)
		eprintln('Java JDK version $jdk_version is not supported')
		eprintln('Please install Java >= 8 JDK or provide a valid path via JAVA_HOME')
		exit(1)
	}

	// Validate build-tools
	if sdk.default_build_tools_version == '' {
		eprintln('No known Android build-tools version(s) could be detected in the SDK.')
		eprintln('(A vab compatible version can be installed with `$exe_name install "build-tools;$sdk.min_supported_build_tools_version"`)')
		exit(1)
	} else if semver.is_valid(sdk.default_build_tools_version) {
		build_tools_semantic_version := semver.from(sdk.default_build_tools_version) or {
			panic(@MOD + '.' + @FN + ':' + @LINE +
				' error converting build-tools version "$sdk.default_build_tools_version" to semantic version.\nsemver: $err')
		}

		if !build_tools_semantic_version.satisfies('>=$sdk.min_supported_build_tools_version') {
			// Some Android tools we need like `apksigner` is currently only available with build-tools >= 24.0.3.
			// (Absolute mess, yes)
			eprintln('Android build-tools version "$sdk.default_build_tools_version" is not supported by ${exe_name}.')
			eprintln('Please install a build-tools version >= $sdk.min_supported_build_tools_version (run `$exe_name install build-tools` to install the default version).')
			eprintln('You can see available build-tools with `$exe_name --list-build-tools`.')
			eprintln('To use a specific version you can use `$exe_name --build-tools "<version>"`.')
			exit(1)
		}
	} else {
		// Not blank but not a recognized format (x.y.z)
		// NOTE It *might* be a SDK managed by the system package manager (apt, pacman etc.) - so we warn about it and go on...
		eprintln('Notice: Android build-tools version "$sdk.default_build_tools_version" is unknown to $exe_name, things might not work as expected.')
	}

	// Validate NDK
	/*
	Currently not possible as version is sniffed from the directory it resides in (which can be anything)
	// Validate Android NDK requirements
	if ndk.found() {
		ndk_semantic_version := semver.from(opt.ndk_version) or {
			panic(@MOD+'.'+@FN+':'+@LINE+' error converting "$opt.ndk_version" to semantic version.\nsemver: $err')
		}
		if ndk_semantic_version.lt(semver.build(21, 1, 0)) {
			eprintln('Android NDK >= 21.1.0 is currently needed. "$opt.ndk_version" is too low.')
			eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
			eprintln('or run `${exe_name} install "ndk;<version>"`')
			exit(1)
		}
	}
	*/
	// API level
	if opt.api_level.i16() < sdk.default_api_level.i16() {
		eprintln('Notice: Android API level $opt.api_level is less than the default level ($sdk.default_api_level).')
	}
	// AAB format
	has_bundletool := env.has_bundletool()
	has_aapt2 := env.has_aapt2()
	if opt.package_format == 'aab' && !(has_bundletool && has_aapt2) {
		if !has_bundletool {
			eprintln('The tool `bundletool` is needed for AAB package building and deployment.')
			eprintln('Please install bundletool manually and provide a path to it via BUNDLETOOL')
			eprintln('or run `$exe_name install bundletool`')
		}
		if !has_aapt2 {
			eprintln('The tool `aapt2` is needed for AAB package building.')
			eprintln('Please install aapt2 manually and provide a path to it via AAPT2')
			eprintln('or run `$exe_name install aapt2`')
		}
		exit(1)
	}
}

fn resolve_options(mut opt Options, exit_on_error bool) {
	// Validate API level
	mut api_level := sdk.default_api_level
	if opt.api_level != '' {
		if sdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			eprintln('Android API level "$opt.api_level" is not available in SDK.')
			eprintln('Falling back to default "$api_level"')
		}
	}
	if api_level == '' {
		eprintln('Android API level "$opt.api_level" is not available in SDK.')
		eprintln('It can be installed with `$exe_name install "platforms;android-<API LEVEL>"`')
		if exit_on_error {
			exit(1)
		}
	}
	if api_level.i16() < sdk.min_supported_api_level.i16() {
		eprintln('Android API level "$api_level" is less than the supported level ($sdk.min_supported_api_level).')
		eprintln('A vab compatible version can be installed with `$exe_name install "platforms;android-$sdk.min_supported_api_level"`')
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
			eprintln('Android build-tools version "$opt.build_tools" is not available in SDK.')
			eprintln('(It can be installed with `$exe_name install "build-tools;$opt.build_tools"`)')
			eprintln('Falling back to default $build_tools_version')
		}
	}
	if build_tools_version == '' {
		eprintln('No known Android build-tools version(s) could be detected in the SDK.')
		eprintln('(A vab compatible version can be installed with `$exe_name install "build-tools;$sdk.min_supported_build_tools_version"`)')
		if exit_on_error {
			exit(1)
		}
	}

	opt.build_tools = build_tools_version

	// Validate NDK version
	mut ndk_version := ndk.default_version()
	if opt.ndk_version != '' {
		if ndk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android NDK version $opt.ndk_version is not available.')
			// eprintln('(It can be installed with `$exe_name install "ndk;${opt.build_tools}"`)')
			eprintln('Falling back to default $ndk_version')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version $opt.ndk_version is not available.')
		// eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		if exit_on_error {
			exit(1)
		}
	}

	opt.ndk_version = ndk_version

	// Resolve output
	default_file_name := opt.app_name.replace(os.path_separator.str(), '').replace(' ',
		'_').to_lower()

	mut output_file := ''
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
	opt.output = output_file

	// Java package ids/names are integrated hard into the eco-system
	opt.lib_name = opt.app_name.replace(' ', '_').to_lower()

	if os.getenv('KEYSTORE_PASSWORD') != '' {
		opt.keystore_password = os.getenv('KEYSTORE_PASSWORD')
	}
	if os.getenv('KEYSTORE_ALIAS_PASSWORD') != '' {
		opt.keystore_alias_password = os.getenv('KEYSTORE_ALIAS_PASSWORD')
	}
}

fn extend_options_from_dot_vab(mut opt Options) {
	// Look up values in input .vab file next to input if no flags or defaults was set
	if opt.package_id == android.default_package_id || opt.activity_name == ''
		|| opt.app_name == android.default_app_name || opt.icon == ''
		|| opt.package_overrides_path == '' {
		dot_vab_file := dot_vab_path(opt.input)
		dot_vab := os.read_file(dot_vab_file) or { '' }
		if dot_vab.len > 0 {
			if opt.icon == '' && dot_vab.contains('icon:') {
				vab_icon := dot_vab.all_after('icon:').all_before('\n').replace("'", '').replace('"',
					'').trim(' ')
				if vab_icon != '' {
					if opt.verbosity > 1 {
						println('Using icon "vab_icon" from .vab file "$dot_vab_file"')
					}
					opt.icon = vab_icon
				}
			}
			if opt.app_name == android.default_app_name && dot_vab.contains('app_name:') {
				vab_app_name := dot_vab.all_after('app_name:').all_before('\n').replace("'",
					'').replace('"', '').trim(' ')
				if vab_app_name != '' {
					if opt.verbosity > 1 {
						println('Using app name "vab_app_name" from .vab file "$dot_vab_file"')
					}
					opt.app_name = vab_app_name
				}
			}
			if opt.package_id == android.default_package_id && dot_vab.contains('package_id:') {
				vab_package_id := dot_vab.all_after('package_id:').all_before('\n').replace("'",
					'').replace('"', '').trim(' ')
				if vab_package_id != '' {
					if opt.verbosity > 1 {
						println('Using package id "$vab_package_id" from .vab file "$dot_vab_file"')
					}
					opt.package_id = vab_package_id
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
							vab_package_overrides_path = vab_package_overrides_path.replace_once(
								'.' + os.path_separator, dot_vab_file_dir + os.path_separator)
						} else {
							// vab_package_overrides_path.starts_with('..'+os.path_separator)
							vab_package_overrides_path = vab_package_overrides_path.replace_once(
								'..' + os.path_separator, os.dir(dot_vab_file_dir) +
								os.path_separator)
						}
					}
					if opt.verbosity > 1 {
						println('Using package overrides in "$vab_package_overrides_path" from .vab file "$dot_vab_file"')
					}
					opt.package_overrides_path = vab_package_overrides_path
				}
			}
			if opt.activity_name == '' && dot_vab.contains('activity_name:') {
				vab_activity := dot_vab.all_after('activity_name:').all_before('\n').replace("'",
					'').replace('"', '').trim(' ')
				if vab_activity != '' {
					if opt.verbosity > 1 {
						println('Using activity name "$vab_activity" from .vab file "$dot_vab_file"')
					}
					opt.activity_name = vab_activity
				}
			}
		}
	}
}

fn vab_commit_hash() string {
	mut hash := ''
	git_exe := os.find_abs_path_of_executable('git') or { '' }
	if git_exe != '' {
		mut git_cmd := 'git -C "$exe_dir" rev-parse --short HEAD'
		$if windows {
			git_cmd = 'git.exe -C "$exe_dir" rev-parse --short HEAD'
		}
		res := os.execute(git_cmd)
		if res.exit_code == 0 {
			hash = res.output
		}
	}
	return hash
}

fn doctor(opt Options) {
	sdkm := env.sdkmanager()
	env_managable := env.managable()
	env_vars := os.environ()

	// Validate Android `sdkmanager` tool
	// Just warnings/notices as `sdkmanager` isn't used to in the build process.
	if sdkm == '' {
		eprintln('No "sdkmanager" could be detected.\n')
		if env_managable {
			eprintln('You can run `$exe_name install cmdline-tools` to install it.')
		}
		eprintln('You can set the SDKMANAGER env variable or try your luck with `$exe_name install auto`.')
		eprintln('Please see https://stackoverflow.com/a/61176718/1904615 for more help.\n')
	} else {
		if !env_managable {
			sdk_is_writable := os.is_writable(sdk.root())
			if !sdk_is_writable {
				eprintln('The SDK at "$sdk.root()" is not writable.')
				eprintln("`$exe_name` is not able to control the SDK and it's dependencies.")
			} else {
				eprintln('The detected `sdkmanager` seems outdated or incompatible with the Java version used.')
				eprintln("For `$exe_name` to control it's own dependencies, please update `sdkmanager` found in:")
				eprintln('"$sdkm"')
				eprintln('or use a Java version that is compatible with your `sdkmanager`.')
				eprintln('You can set the SDKMANAGER env variable or try your luck with `$exe_name install auto`.')
				eprintln('Please see https://stackoverflow.com/a/61176718/1904615 for more help.\n')
			}
		}
	}

	// vab section
	println('$exe_name
	Version $exe_version $exe_git_hash
	Path "$exe_dir"')

	// Shell environment
	print_var_if_set := fn (vars map[string]string, var_name string) {
		if var_name in vars {
			println('\t$var_name=' + os.getenv(var_name))
		}
	}
	print_var_if_set(env_vars, 'ANDROID_HOME')
	print_var_if_set(env_vars, 'ANDROID_SDK_ROOT')
	print_var_if_set(env_vars, 'ANDROID_NDK_ROOT')
	print_var_if_set(env_vars, 'SDKMANAGER')
	print_var_if_set(env_vars, 'ADB')
	print_var_if_set(env_vars, 'BUNDLETOOL')
	print_var_if_set(env_vars, 'AAPT2')
	print_var_if_set(env_vars, 'JAVA_HOME')
	print_var_if_set(env_vars, 'VEXE')

	// Java section
	println('Java
	JDK
		Version $java.jdk_version()
		Path "$java.jdk_root()"')

	// Android section
	println('Android
	ENV
		sdkmanager "$sdkm"
		sdkmanager.version "$env.sdkmanager_version()"
		Managable: $env_managable
	SDK
		Path "$sdk.root()"
		Writable ${os.is_writable(sdk.root())}
	NDK
		Version $opt.ndk_version
		Path "$ndk.root()"
		Side-by-side $ndk.is_side_by_side()
	Build
		API $opt.api_level
		Build-tools $opt.build_tools
	Packaging
		Format $opt.package_format')

	if env.has_bundletool() {
		println('\t\tBundletool "$env.bundletool()"')
	}
	if env.has_aapt2() {
		println('\t\tAAPT2 "$env.aapt2()"')
	}

	if opt.keystore != '' || opt.keystore_alias != '' {
		println('\tKeystore')
		println('\t\tFile $opt.keystore')
		println('\t\tAlias $opt.keystore_alias')
	}
	// Product section
	println('Product
	Name "$opt.app_name"
	Package ID "$opt.package_id"
	Output "$opt.output"')

	// V section
	println('V
	Version $vxt.version() $vxt.version_commit_hash()
	Path "$vxt.home()"')
	if opt.v_flags.len > 0 {
		println('\tFlags $opt.v_flags')
	}
	// Print output of `v doctor` if v is found
	if vxt.found() {
		println('')
		v_cmd := [
			vxt.vexe(),
			'doctor',
		]
		v_res := os.execute(v_cmd.join(' '))
		out_lines := v_res.output.split('\n')
		for line in out_lines {
			println('\t$line')
		}
	}
}

// dot_vab_path returns the path to the `.vab` file next to `file_or_dir_path` if found, an empty string otherwise.
pub fn dot_vab_path(file_or_dir_path string) string {
	if os.is_dir(file_or_dir_path) {
		if os.is_file(os.join_path(file_or_dir_path, '.vab')) {
			return os.join_path(file_or_dir_path, '.vab')
		}
	} else {
		if os.is_file(os.join_path(os.dir(file_or_dir_path), '.vab')) {
			return os.join_path(os.dir(file_or_dir_path), '.vab')
		}
	}
	return ''
}

fn launch_cmd(args []string) int {
	mut cmd := args[0]
	cmd_args := args[1..]
	if cmd.starts_with('test-') {
		cmd = cmd.all_after('test-')
	}
	v := vxt.vexe()
	exe := os.join_path(exe_dir, 'cmd', cmd)
	if os.is_executable(v) {
		hash_file := os.join_path(exe_dir, 'cmd', '.' + cmd + '.hash')

		mut hash := ''
		if os.is_file(hash_file) {
			hash = os.read_file(hash_file) or { '' }
		}
		if hash != exe_git_hash {
			v_cmd := [
				v,
				exe + '.v',
				'-o',
				exe,
			]
			res := os.execute(v_cmd.join(' '))
			if res.exit_code < 0 {
				panic(@MOD + '.' + @FN + ' failed compiling "$cmd": $res.output')
			}
			if res.exit_code == 0 {
				os.write_file(hash_file, exe_git_hash) or {}
			} else {
				vcmd := v_cmd.join(' ')
				eprintln(@MOD + '.' + @FN + ' "$vcmd" failed.')
				eprintln(res.output)
				return 1
			}
		}
	}
	exec := (exe + ' ' + cmd_args.join(' ')).trim_right(' ')
	if os.is_executable(exe) {
		res := os.execute(exec)
		if res.exit_code == 0 {
			print(res.output)
			os.flush()
			return 0
		} else {
			eprintln(res.output)
			return 1
		}
	}
	v_message := if !os.is_executable(v) { ' (v was not found)' } else { '' }
	eprintln(@MOD + '.' + @FN + ' failed executing "$exec"$v_message')
	return 1
}

fn version() string {
	mut v := '0.0.0'
	vmod := @VMOD_FILE
	if vmod.len > 0 {
		if vmod.contains('version:') {
			v = vmod.all_after('version:').all_before('\n').replace("'", '').replace('"',
				'').trim(' ')
		}
	}
	return v
}
