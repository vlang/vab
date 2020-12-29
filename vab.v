module main

import os
import flag

import vxt
import semver// as semver

import java

import android
import android.sdk
import android.ndk
import android.env

const (
	exe_version = '0.2.0'
	exe_name    = os.file_name(os.executable())
	exe_dir     = os.dir(os.real_path(os.executable()))
	rip_vflags  = ['-autofree','-cg','-prod', 'run']
)

struct Options {
	// App essentials
	app_name		string
	package_id		string
	icon			string
	// Internals
	verbosity		int
	work_dir		string
	// Build, packaging and deployment
	version_code	int
	device_id		string
	keystore		string
	keystore_alias	string
	// Build specifics
	c_flags			[]string // flags passed to the C compiler(s)
	archs			[]string
	// Deploy specifics
	run				bool
	// Detected environment
	dump_usage		bool
	list_ndks		bool
	list_apis		bool
	list_build_tools bool
mut:
	input			string
	output			string
	// Build and packaging
	v_flags			[]string // flags passed to the V compiler
	lib_name		string
	assets_extra	[]string
	keystore_password string
	keystore_alias_password	string
	// Build specifics
	build_tools		string
	api_level		string
	ndk_version		string
}

fn main() {
	mut args := os.args.clone()
	mut v_flags := []string{}
	mut cmd_flags := []string{}

	// Indentify special flags in args before FlagParser ruin them.
	// E.g. the -autofree flag will result in dump_env being called for some weird reason???
	for special_flag in rip_vflags {
		if special_flag in args {
			if special_flag.starts_with('-') {
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

	mut opt := Options {

		assets_extra: fp.string_multi('assets', `a`, 'Asset dir(s) to include in build')
		v_flags: fp.string_multi('flag', `f`, 'Additional flags for the V compiler')
		c_flags: fp.string_multi('cflag', `c`, 'Additional flags for the C compiler')
		archs: fp.string('archs', 0, '', 'Comma separated string with any of "${android.default_archs}"').split(',')

		device_id: fp.string('device', `d`, '', 'Deploy to device <id>. Use "auto" to use first available.')
		run: 'run' in cmd_flags //fp.bool('run', `r`, false, 'Run the app on the device after successful deployment.')

		keystore: fp.string('keystore', 0, '', 'Use this keystore file to sign the package')
		keystore_alias: fp.string('keystore-alias', 0, '', 'Use this keystore alias from the keystore file to sign the package')

		dump_usage: fp.bool('help', 0, false, 'Show this help message and exit')

		app_name: fp.string('name', 0, android.default_app_name, 'Pretty app name')
		package_id: fp.string('package-id', 0, android.default_package_id, 'App package ID (e.g. "org.v.app")')
		icon: fp.string('icon', 0, '', 'App icon')
		version_code: fp.int('version-code', 0, 0, 'Build version code (android:versionCode)')

		output: fp.string('output', `o`, '', 'Path to output (dir/file)')

		verbosity: verbosity

		build_tools: fp.string('build-tools', 0, '', 'Version of build-tools to use (--list-build-tools)')
		api_level: fp.string('api', 0, '', 'Android API level to use (--list-apis)')

		ndk_version: fp.string('ndk-version', 0, '', 'Android NDK version to use (--list-ndks)')

		work_dir: os.join_path(os.temp_dir(), exe_name.replace(' ','_').to_lower())

		list_ndks: fp.bool('list-ndks', 0, false, 'List available NDK versions')
		list_apis: fp.bool('list-apis', 0, false, 'List available API levels')
		list_build_tools: fp.bool('list-build-tools', 0, false, 'List available Build-tools versions')
	}

	additional_args := fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		exit(1)
	}

	if additional_args.len > 1 {
		if additional_args[0] == 'install' {
			install_arg := additional_args[1]
			res := env.install(install_arg, opt.verbosity)
			if res == 0 && opt.verbosity > 0 {
				if install_arg != 'auto' {
					println('Installed ${install_arg} successfully.')
				} else {
					println('Installed all dependencies successfully.')
				}
			}
			exit( res )
		}
	}

	if opt.list_ndks {
		for ndk_v in ndk.versions_available() {
			println(ndk_v)
		}
		exit(0)
	}

	if opt.list_apis {
		for api in sdk.apis_available() {
			println(api)
		}
		exit(0)
	}

	if opt.list_build_tools {
		for btv in sdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}

	// Validate environment
	check_essentials()
	resolve_options(mut opt)
	// Merge flags captured before FlagParser
	v_flags << opt.v_flags
	opt.v_flags = v_flags
	// Call the doctor at this point
	if additional_args.len > 0 {
		if additional_args[0] == 'doctor' {
			doctor(opt)
			exit(0)
		}
	}
	// Validate environment after options has been resolved
	validate_env(opt)

	if fp.args.len == 0 {
		eprintln('No arguments given')
		println(fp.usage())
		exit(1)
	}
	if opt.dump_usage {
		println(fp.usage())
		exit(0)
	}
	input := fp.args[fp.args.len-1]

	input_ext := os.file_ext(input)
	accepted_input_files := ['.v','.apk','.aab']

	if ! (os.is_dir(input) || input_ext in accepted_input_files) {
		println(fp.usage())
		eprintln('$exe_name requires input to be a V file, an APK, AAB or a V source(s) directory')
		exit(1)
	}
	opt.input = input

	kill_adb := os.getenv('VAB_KILL_ADB') != ''

	mut run := ''
	if opt.run {
		//TODO 'com.package.name/com.package.name.ActivityName'
		mut package_id := opt.package_id
		if package_id == '' {
			package_id = android.default_package_id
		}
		run = '${package_id}/${package_id}.Native'
	}

	deploy_opt := android.DeployOptions {
		verbosity: opt.verbosity
		device_id: opt.device_id
		deploy_file: opt.output
		kill_adb: kill_adb
		run: run
	}

	if input_ext in accepted_input_files {
		if opt.device_id != '' {
			if ! android.deploy(deploy_opt) {
				eprintln('$exe_name deployment didn\'t succeed')
				exit(1)
			} else {
				if opt.verbosity > 0 {
					println('Deployed to ${opt.device_id} successfully')
				}
				exit(1)
			}
		}
	}

	comp_opt := android.CompileOptions {
		verbosity:		opt.verbosity
		v_flags:		opt.v_flags
		c_flags:		opt.c_flags
		archs:			opt.archs

		work_dir:		opt.work_dir
		input:			opt.input

		ndk_version:	opt.ndk_version
		lib_name:		opt.lib_name
		api_level:		opt.api_level
	}
	if ! android.compile(comp_opt) {
		eprintln('$exe_name compiling didn\'t succeed')
		exit(1)
	}

	// Keystore file
	mut keystore := opt.keystore
	if !os.is_file(keystore) {
		if keystore != '' {
			println('Couldn\'t locate "$keystore"')
		}
		eprintln('Notice: Using default debug.keystore')
		keystore = ''
	}
	if keystore == '' {
		keystore = os.join_path(exe_dir,'debug.keystore')
	}
	pck_opt := android.PackageOptions {
		verbosity:					opt.verbosity
		work_dir:					opt.work_dir

		api_level:					opt.api_level
		build_tools:				opt.build_tools

		app_name:					opt.app_name
		lib_name:					opt.lib_name
		package_id:					opt.package_id
		icon:						opt.icon
		version_code:				opt.version_code

		v_flags:					opt.v_flags

		input:						opt.input
		assets_extra:				opt.assets_extra
		output_file:				opt.output
		keystore: 					keystore
		keystore_alias: 			opt.keystore_alias
		keystore_password:			opt.keystore_password
		keystore_alias_password:	opt.keystore_alias_password
		base_files:					os.join_path(exe_dir, 'platforms', 'android')
	}
	if ! android.package(pck_opt) {
		eprintln('Packaging didn\'t succeed')
		exit(1)
	}

	if opt.device_id != '' {
		if ! android.deploy(deploy_opt) {
			eprintln('Deployment didn\'t succeed')
			exit(1)
		} else {
			if opt.verbosity > 0 {
				println('Deployed to device (${opt.device_id}) successfully')
			}
		}
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `$exe_name --device <id> ${os.real_path(opt.output)}` to deploy package')
		}
	}
}

fn check_essentials() {

	// Validate V install
	if vxt.vexe() == '' {
		eprintln('No V install could be detected')
		eprintln('Please install V from https://github.com/vlang/v')
		eprintln('or provide a valid path to V via VEXE env variable')
		exit(1)
	}

	// Validate Java requirements
	if !java.jdk_found() {
		eprintln('No Java install(s) could be detected')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	// Validate Android SDK requirements
	if !sdk.found() {
		eprintln('No Android SDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `${exe_name} install auto`')
		exit(1)
	}

	// Validate Android NDK requirements
	if !ndk.found() {
		eprintln('No Android NDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
		eprintln('or run `${exe_name} install ndk`')
		exit(1)
	}
}

fn validate_env(opt Options) {

	jdk_version := java.jdk_version()
	if jdk_version == '' {
		eprintln('No Java JDK install(s) could be detected')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	jdk_semantic_version := semver.from(jdk_version) or { panic(err) }
	if !jdk_semantic_version.ge(semver.build(1, 8, 0)) { // NOTE When did this break:.satisfies('1.8.*') ???
		// Some Android tools like `sdkmanager` currently only run with Java 8 JDK (1.8.x).
		// (Absolute mess, yes)
		eprintln('Java version ${jdk_version} is not supported')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	// Validate further Android SDK
	if sdk.sdkmanager() == '' {
		eprintln('No "sdkmanager" could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `${exe_name} install tools`')
		exit(1)
	}

	build_tools_semantic_version := semver.from(sdk.default_build_tools_version) or { panic(err) }

	if !build_tools_semantic_version.ge(semver.build(24, 0, 3)) { // NOTE When did this break:.satisfies('>=24.0.3') ???
		// Some Android tools we need like `apksigner` is currently only available with build-tools >= 24.0.3.
		// (Absolute mess, yes)
		eprintln('Android build-tools version ${sdk.default_build_tools_version} is not supported')
		eprintln('Please install build-tools version >= 24.0.3')
		eprintln('or run `${exe_name} install build-tools`')
		exit(1)
	}

	// API level
	if opt.api_level.i16() < sdk.default_api_level.i16() {
		eprintln('Notice: Android API level ${opt.api_level} is less than the recomended level (${sdk.default_api_level}).')
	}
}

fn resolve_options(mut opt Options) {

	// Validate API level
	mut api_level := sdk.default_api_level
	if opt.api_level != '' {
		if sdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			eprintln('Android API level ${opt.api_level} is not available in SDK.')
			//eprintln('(It can be installed with `$exe_name install android-api-${opt.api_level}`)')
			eprintln('Falling back to default ${api_level}')
		}
	}
	if api_level == '' {
		eprintln('Android API level ${opt.api_level} is not available in SDK.')
		eprintln('It can be installed with `$exe_name install "platform;android-${opt.api_level}"`')
		exit(1)
	}
	if api_level.i16() < sdk.min_supported_api_level.i16() {
		eprintln('Android API level ${api_level} is less than the supported level (${sdk.min_supported_api_level}).')
		exit(1)
	}

	opt.api_level = api_level

	// Validate build-tools version
	mut build_tools_version := sdk.default_build_tools_version
	if opt.build_tools != '' {
		if sdk.has_build_tools(opt.build_tools) {
			build_tools_version = opt.build_tools
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android build-tools version ${opt.build_tools} is not available in SDK.')
			//eprintln('(It can be installed with `$exe_name install android-build-tools-${opt.build_tools}`)')
			eprintln('Falling back to default ${build_tools_version}')
		}
	}
	if build_tools_version == '' {
		eprintln('Android build-tools version ${opt.build_tools} is not available in SDK.')
		//eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.build_tools = build_tools_version

	// Validate ndk version
	mut ndk_version := ndk.default_version()
	if opt.ndk_version != '' {
		if ndk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android NDK version ${opt.ndk_version} is not available.')
			//eprintln('(It can be installed with `$exe_name install android-build-tools-${opt.build_tools}`)')
			eprintln('Falling back to default ${ndk_version}')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version ${opt.ndk_version} is not available.')
		//eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.ndk_version = ndk_version

	// Output specific
	default_file_name := opt.app_name.replace(os.path_separator.str(),'').replace(' ','_').to_lower()

	mut output_file := ''
	if opt.output != '' {
		ext := os.file_ext(opt.output)
		if ext != '' {
			output_file = opt.output.all_before(ext)
		} else {
			output_file = os.join_path(opt.output.trim_right(os.path_separator),default_file_name)
		}
	} else {
		output_file = default_file_name
	}
	output_file += '.apk'
	opt.output = output_file

	// TODO can be supported when we can manipulate or generate AndroidManifest.xml + sources from code
	// Java package ids/names are integrated hard into the eco-system
	opt.lib_name = opt.app_name.replace(' ','_').to_lower()

	if os.getenv('KEYSTORE_PASSWORD') != '' {
		opt.keystore_password = os.getenv('KEYSTORE_PASSWORD')
	}
	if os.getenv('KEYSTORE_ALIAS_PASSWORD') != '' {
		opt.keystore_alias_password = os.getenv('KEYSTORE_ALIAS_PASSWORD')
	}
}

fn doctor(opt Options) {
	println('$exe_name
	Version $exe_version
	Path "$exe_dir"')
	println('V
	Version $vxt.version()
	Path "$vxt.home()"')
	if opt.v_flags.len > 0 {
		println('\tFlags ${opt.v_flags}')
	}
	println('Java
	JDK
		Version ${java.jdk_version()}
		Path "$java.jdk_root()"
	Android
		SDK
			Path "$sdk.root()"
			Tool.sdkmanager "$sdk.sdkmanager()"
			Writable ${env.can_install()}
		NDK
			Version ${opt.ndk_version}
			Path "$ndk.root()"
			Side-by-side ${ndk.is_side_by_side()}
		Build
			API ${opt.api_level}
			Build-tools ${opt.build_tools}')
	if opt.keystore != '' || opt.keystore_alias != '' {
		println('\tKeystore')
		println('\t\tFile ${opt.keystore}')
		println('\t\tAlias ${opt.keystore_alias}')
	}
	println('Product
	Name "${opt.app_name}"
	Package "$opt.package_id"
	Output "$opt.output"
	')
}
