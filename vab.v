// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module main

import os
import flag
import vab.cli
import vab.android
import vab.android.sdk
import vab.android.ndk
import vab.android.env

fn main() {
	// Collect user flags in an extended manner.
	// Start with defaults -> overwrite by VAB_FLAGS -> overwrite by commandline flags -> extend by .vab file entries.
	mut opt := cli.Options{}
	mut fp := &flag.FlagParser(0)

	env_vab_flags := os.getenv('VAB_FLAGS')
	if env_vab_flags != '' {
		mut vab_flags := [os.args[0]]
		vab_flags << cli.string_to_args(env_vab_flags) or {
			eprintln('Error while parsing `VAB_FLAGS`: $err')
			eprintln('Use `vab -h` to see all flags')
			exit(1)
		}
		opt, fp = cli.args_to_options(vab_flags, opt) or {
			eprintln('Error while parsing `VAB_FLAGS`: $err')
			eprintln('Use `vab -h` to see all flags')
			exit(1)
		}
	}

	opt, fp = cli.args_to_options(os.args, opt) or {
		eprintln('Error while parsing `os.args`: $err')
		eprintln('Use `vab -h` to see all flags')
		exit(1)
	}

	$if vab_debug_options ? {
		eprintln(opt)
		eprintln(vab_flags)
		eprintln(os.args)
	}

	if opt.dump_usage {
		println(fp.usage())
		exit(0)
	}

	if opt.list_ndks {
		if !ndk.found() {
			eprintln('No NDK could be found. Please use `$cli.exe_short_name doctor` to get more information.')
			exit(1)
		}
		for ndk_v in ndk.versions_available() {
			println(ndk_v)
		}
		exit(0)
	}

	if opt.list_apis {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `$cli.exe_short_name doctor` to get more information.')
			exit(1)
		}
		for api in sdk.apis_available() {
			println(api)
		}
		exit(0)
	}

	if opt.list_build_tools {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `$cli.exe_short_name doctor` to get more information.')
			exit(1)
		}
		for btv in sdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}
	// All flags after this requires an input argument
	if fp.args.len == 0 {
		eprintln('No arguments given')
		eprintln('Use `vab -h` to see all flags')
		exit(1)
	}

	if opt.additional_args.len > 1 {
		if opt.additional_args[0] == 'install' {
			install_arg := opt.additional_args[1]
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

	// Convert v flags captured to option field
	if '-prod' in opt.v_flags {
		opt.is_prod = true
		opt.v_flags.delete(opt.v_flags.index('-prod'))
	}

	// Call the doctor at this point
	if opt.additional_args.len > 0 {
		if opt.additional_args[0] == 'doctor' {
			// Validate environment
			cli.check_essentials(false)
			opt.resolve(false)
			cli.doctor(opt)
			exit(0)
		}
	}
	// Validate environment
	cli.check_essentials(true)
	opt.resolve(true)

	input := fp.args.last()
	cli.validate_input(input) or {
		eprintln('$cli.exe_short_name: $err')
		exit(1)
	}
	opt.input = input

	opt.resolve_output()

	opt.extend_from_dot_vab()

	kill_adb := os.getenv('VAB_KILL_ADB') != ''

	// If no package id or activity name has been set at this point,
	// use the defaults
	mut package_id := opt.package_id
	mut activity_name := opt.activity_name
	if package_id == '' {
		package_id = android.default_package_id
	}
	if activity_name == '' {
		activity_name = android.default_activity_name
	}

	// Validate environment after options and input has been resolved
	opt.validate_env()

	mut run := ''
	if opt.run {
		run = '$package_id/${package_id}.$activity_name'
		if opt.verbosity > 1 {
			println('Should run "$package_id/${package_id}.$activity_name"')
		}
	}

	// If no device id has been set at this point,
	// check for ENV vars
	mut device_id := opt.device_id
	if device_id == '' {
		device_id = os.getenv('ANDROID_SERIAL')
		if opt.verbosity > 1 && device_id != '' {
			println('Using device "$device_id" from ANDROID_SERIAL env variable')
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
	mut keystore := android.Keystore{
		path: opt.keystore
		password: opt.keystore_password
		alias: opt.keystore_alias
		alias_password: opt.keystore_alias_password
	}
	if !os.is_file(keystore.path) {
		if keystore.path != '' {
			eprintln('Keystore "$keystore.path" is not a valid file')
			eprintln('Notice: Signing with debug keystore')
		}
		keystore = android.default_keystore(cli.cache_directory) or {
			eprintln('Getting a default keystore failed.\n$err')
			exit(1)
		}
	} else {
		keystore = android.resolve_keystore(keystore) or {
			eprintln('Could not resolve keystore.\n$err')
			exit(1)
		}
	}
	if opt.verbosity > 1 {
		println('Output will be signed with keystore at "$keystore.path"')
	}

	mut log_tags := opt.log_tags
	log_tags << opt.lib_name

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
		clear_device_log: opt.clear_device_log
		device_log: opt.device_log || opt.device_log_raw
		log_mode: if opt.device_log_raw { android.LogMode.raw } else { android.LogMode.filtered }
		log_tags: log_tags
		run: run
	}

	input_ext := os.file_ext(opt.input)

	// Early deployment
	if input_ext in ['.apk', '.aab'] {
		if opt.device_id != '' {
			android.deploy(deploy_opt) or {
				eprintln('$cli.exe_short_name deployment didn\'t succeed.\n$err')
				if deploy_opt.kill_adb {
					kill_adb_on_exit()
				}
				exit(1)
			}
			if opt.verbosity > 0 {
				println('Deployed to $opt.device_id successfully')
			}
			if deploy_opt.kill_adb {
				kill_adb_on_exit()
			}
			exit(0)
		}
	}

	mut archs := opt.archs.filter(it.trim(' ') != '')
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}

	compile_cache_key := if os.is_dir(input) || input_ext == '.v' { opt.input } else { '' }
	comp_opt := android.CompileOptions{
		verbosity: opt.verbosity
		cache: opt.cache
		cache_key: compile_cache_key
		parallel: opt.parallel
		is_prod: opt.is_prod
		gles_version: opt.gles_version
		no_printf_hijack: opt.no_printf_hijack
		v_flags: opt.v_flags
		c_flags: opt.c_flags
		archs: archs
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		lib_name: opt.lib_name
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
	}
	android.compile(comp_opt) or {
		eprintln('$cli.exe_short_name compiling didn\'t succeed.\n$err')
		exit(1)
	}

	pck_opt := android.PackageOptions{
		verbosity: opt.verbosity
		work_dir: opt.work_dir
		is_prod: opt.is_prod
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
		gles_version: opt.gles_version
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
		libs_extra: opt.libs_extra
		output_file: opt.output
		keystore: keystore
		base_files: os.join_path(cli.exe_dir, 'platforms', 'android')
		overrides_path: opt.package_overrides_path
	}
	android.package(pck_opt) or {
		eprintln("Packaging didn't succeed.\n$err")
		exit(1)
	}

	if device_id != '' {
		android.deploy(deploy_opt) or {
			eprintln("Deployment didn't succeed.\n$err")
			if deploy_opt.kill_adb {
				kill_adb_on_exit()
			}
			exit(1)
		}
		if opt.verbosity > 0 {
			println('Deployed to device ($device_id) successfully')
		}
		if deploy_opt.kill_adb {
			kill_adb_on_exit()
		}
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `$cli.exe_short_name --device <id> ${os.real_path(opt.output)}` to deploy package')
		}
	}
}

fn kill_adb_on_exit() {
	uos := os.user_os()
	println('Killing adb ...')
	if uos == 'windows' {
		// os.system('Taskkill /IM adb.exe /F') // TODO Untested
	} else {
		os.system('killall adb')
	}
}
