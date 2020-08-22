module main

import os
import flag

import vxt
import semver

import java

import android
import android.sdk as asdk
import android.ndk as andk

const (
	exe_name	= os.file_name(os.executable())
	exe_dir		= os.base_dir(os.real_path(os.executable()))
)

const (
	default_app_name = 'V Default App'
	default_package_id = 'org.v.android.default.app'
)

const (
	min_supported_api_level = '21'
)

/* fn appendenv(name, value string) {
	os.setenv(name, os.getenv(name)+os.path_delimiter+value, true)
}*/

fn dump(opt Options) {
	println('V')
	println('\tVersion ${vxt.version()}')
	println('\tPath ${vxt.home()}')
	println('Java')
	println('\tJDK')
	println('\t\tVersion ${java.jdk_version()}')
	println('\t\tPath ${java.jdk_root()}')
	println('Android')
	println('\tSDK')
	println('\t\tPath ${asdk.root()}')
	println('\tNDK')
	println('\t\tVersion ${opt.ndk_version}')
	println('\t\tPath ${andk.root()}')
	println('\tBuild')
	println('\t\tAPI ${opt.api_level}')
	println('\t\tBuild-tools ${opt.build_tools}')
	println('Product')
	println('\tName "${opt.app_name}"')
	println('\tPackage ${opt.package_id}')
	println('\tOutput ${opt.output_file}')
	println('')
}

struct Options {
	app_name		string
	package_id	string

	verbosity		int

	work_dir		string

	device_id		string

	dump_env		bool

	list_apis		bool
	list_build_tools bool
mut:
	input			string
	output_file		string
	machine_friendly_app_name string

	build_tools		string
	api_level		string
	ndk_version		string

	assets_extra	[]string
}



fn main() {

	mut fp := flag.new_flag_parser(os.args)
	fp.application(exe_name)
	fp.version('0.1.0')
	fp.description('V Android Bootstrapper')
	//fp.arguments_description('[ARGS] <input>')

	fp.skip_executable()

	verbosity := fp.int_opt('verbosity', `v`, 'Verbosity level') or { 0 }

	mut opt := Options {

		assets_extra: fp.string_multi('assets', `a`, 'Asset dir(s) to include in build')

		device_id: fp.string('device-id', `i`, '', 'Deploy to this device ID after build')
		dump_env: fp.bool('dump', `d`, false, 'Dump the detected environment and exit')

		app_name: fp.string('name', 0, default_app_name, 'Pretty app name')
		package_id: fp.string('package-id', 0, default_package_id, 'App package ID (e.g. "org.v.app")')
		output_file: fp.string('output', `o`, '', 'Path to output file (dir or file)')

		verbosity: verbosity

		build_tools: fp.string('build-tools', 0, '', 'Version of build-tools to use')
		api_level: fp.string('api', 0, '', 'Android API level to use')

		ndk_version: fp.string('ndk-version', 0, '', 'Android NDK version to use')

		work_dir: os.join_path(os.temp_dir(), exe_name.replace(' ','_').to_lower())

		list_apis:  fp.bool('list-api', 0, false, 'List available API levels')
		list_build_tools:  fp.bool('list-build-tools', 0, false, 'List available Build-tools versions')
	}

	fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		return
	}

	/*
	 * Validate environment
	 */
	check_dependencies()

	resolve_options(mut opt)

	if opt.dump_env {
		dump(opt)
		exit(0)
	}

	if opt.list_apis {
		for api in asdk.apis_available() {
			println(api.all_after('android-'))
		}
		exit(0)
	}

	if opt.list_build_tools {
		for btv in asdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}

	if fp.args.len <= 0 {
		println(fp.usage())
		eprintln('$exe_name requires a valid input file or directory')
		exit(1)
	}


	input := fp.args[fp.args.len-1]
	input_ext := os.file_ext(input)

	accepted_input_files := ['.v','.apk','.aab']

	if ! (os.is_dir(input) || input_ext in accepted_input_files) {
		println(fp.usage())
		eprintln('$exe_name requires input to be a V file, an APK, AAB or or V sources a directory')
		exit(1)
	}
	opt.input = input

	deploy_opt := android.DeployOptions {
		verbosity: opt.verbosity
		device_id: opt.device_id
		deploy_file: opt.output_file
	}

	if input_ext in accepted_input_files {
		if opt.device_id != '' {
			if ! android.deploy(deploy_opt) {
				eprintln('Deployment didn\'t succeed')
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
		work_dir:		opt.work_dir
		input:			opt.input

		verbosity:		opt.verbosity

		ndk_version:	opt.ndk_version
		machine_friendly_app_name:	opt.machine_friendly_app_name
		api_level:		opt.api_level
	}
	if ! android.compile(comp_opt) {
		eprintln('Compiling didn\'t succeed')
		exit(1)
	}

	pck_opt := android.PackageOptions {
		verbosity:		opt.verbosity
		work_dir:		opt.work_dir

		api_level:		opt.api_level
		build_tools:	opt.build_tools

		input:			opt.input
		assets_extra:	opt.assets_extra
		output_file:	opt.output_file
		keystore: 		os.join_path(exe_dir,'debug.keystore')
		base_files:		os.join_path(exe_dir, 'platforms', 'android')
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
				println('Deployed to ${opt.device_id} successfully')
			}
		}
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output_file)}')
			println('Use `$exe_name --device-id ${os.real_path(opt.output_file)}` to deploy package')
		}
	}
}

fn check_dependencies() {

	// Validate V install
	if vxt.vexe() == '' {
		eprintln('No V install could be detected')
		eprintln('Please provide a valid path to V via VEXE env variable')
		eprintln('or install V from https://github.com/vlang/v')
		exit(1)
	}

	// Validate Java requirements
	if ! java.jdk_found() {
		eprintln('No Java install(s) could be detected')
		eprintln('Please install Java 8 JDK')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	jdk_version := java.jdk_version()
	if jdk_version == '' {
		eprintln('No Java JDK install(s) could be detected')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	jdk_semantic_version := semver.from(jdk_version) or { panic(err) }

	if ! jdk_semantic_version.satisfies('1.8.*') {
		// Some Android tools like `sdkmanager` currently only run with Java 8 JDK (1.8.x).
		// (Absolute mess, yes)
		eprintln('Java version ${jdk_version} is not supported')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		eprintln('(Currently Java 8 (1.8.x) is the only Java version supported by the Android SDK)')
		exit(1)
	}

	// Validate Android SDK requirements
	if ! asdk.found() {
		eprintln('No Android SDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `$exe_name install android-sdk`')
		exit(1)
	}

	// Validate Android NDK requirements
	if ! andk.found() {
		eprintln('No Android NDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
		eprintln('or run `$exe_name install android-ndk`')
		exit(1)
	}
}

fn resolve_options(mut opt Options) {

	// Validate API level
	mut api_level := asdk.default_api_level
	if opt.api_level != '' {
		if asdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			println('Android API level ${opt.api_level} is not available in SDK.')
			//println('(It can be installed with `$exe_name install android-api-${opt.api_level}`)')
			println('Falling back to default ${api_level}')
		}
	}
	if api_level == '' {
		eprintln('Android API level ${opt.api_level} is not available in SDK.')
		//eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		exit(1)
	}
	if api_level.i16() < 20 {
		eprintln('Android API level ${api_level} is less than the recomended level (${min_supported_api_level}).')
		exit(1)
	}

	opt.api_level = api_level

	// Validate build-tools version
	mut build_tools_version := asdk.default_build_tools_version
	if opt.build_tools != '' {
		if asdk.has_build_tools(opt.build_tools) {
			build_tools_version = opt.build_tools
		} else {
			// TODO FIX Warnings and add install function
			println('Android build-tools version ${opt.build_tools} is not available in SDK.')
			//println('(It can be installed with `$exe_name install android-build-tools-${opt.build_tools}`)')
			println('Falling back to default ${build_tools_version}')
		}
	}
	if build_tools_version == '' {
		eprintln('Android build-tools version ${opt.build_tools} is not available in SDK.')
		//eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.build_tools = build_tools_version

	// Validate ndk version
	mut ndk_version := andk.default_version()
	if opt.ndk_version != '' {
		if andk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			println('Android NDK version ${opt.ndk_version} is not available.')
			//println('(It can be installed with `$exe_name install android-build-tools-${opt.build_tools}`)')
			println('Falling back to default ${ndk_version}')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version ${opt.ndk_version} is not available.')
		//eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.ndk_version = ndk_version

	// Output specific
	default_file_name := opt.app_name.replace(' ','_').to_lower()

	mut output_file := ''
	if opt.output_file != '' {
		output_file = opt.output_file.all_before(os.file_ext(opt.output_file))
	} else {
		output_file = default_file_name
	}
	output_file += '.apk'
	opt.output_file = output_file

	// TODO can be supported when we can manipulate or generate AndroidManifest.xml + sources from code
	// Java package ids/names are integrated hard into the eco-system
	opt.machine_friendly_app_name = 'v'  //opt.app_name.replace(' ','_').to_lower()
}
