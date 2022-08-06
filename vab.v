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

	opt = cli.options_from_env(opt) or {
		eprintln('Error while parsing `VAB_FLAGS`: $err')
		eprintln('Use `$cli.exe_short_name -h` to see all flags')
		exit(1)
	}

	opt, fp = cli.args_to_options(os.args, opt) or {
		eprintln('Error while parsing `os.args`: $err')
		eprintln('Use `$cli.exe_short_name -h` to see all flags')
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

	// Validate environment after options and input has been resolved
	opt.validate_env()

	opt.ensure_launch_fields()

	// Keystore file
	keystore := opt.resolve_keystore() or {
		eprintln('$cli.exe_short_name: could not resolve keystore: $err')
		exit(1)
	}

	ado := opt.as_android_deploy_options() or {
		eprintln('Could not create deploy options.\n$err')
		exit(1)
	}
	deploy_opt := android.DeployOptions{
		...ado
		keystore: keystore
	}

	if opt.verbosity > 1 {
		println('Output will be signed with keystore at "$deploy_opt.keystore.path"')
	}

	input_ext := os.file_ext(opt.input)

	// Early deployment
	if input_ext in ['.apk', '.aab'] {
		if deploy_opt.device_id != '' {
			deploy(deploy_opt)
			exit(0)
		}
	}

	aco := opt.as_android_compile_options()
	comp_opt := android.CompileOptions{
		...aco
		cache_key: if os.is_dir(input) || input_ext == '.v' { opt.input } else { '' }
	}
	android.compile(comp_opt) or {
		eprintln('$cli.exe_short_name compiling didn\'t succeed.\n$err')
		exit(1)
	}

	apo := opt.as_android_package_options()
	pck_opt := android.PackageOptions{
		...apo
		keystore: keystore
	}
	android.package(pck_opt) or {
		eprintln("Packaging didn't succeed.\n$err")
		exit(1)
	}

	if deploy_opt.device_id != '' {
		deploy(deploy_opt)
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `$cli.exe_short_name --device <id> ${os.real_path(opt.output)}` to deploy package')
		}
	}
}

fn deploy(deploy_opt android.DeployOptions) {
	android.deploy(deploy_opt) or {
		eprintln('$cli.exe_short_name deployment didn\'t succeed.\n$err')
		if deploy_opt.kill_adb {
			cli.kill_adb()
		}
		exit(1)
	}
	if deploy_opt.verbosity > 0 {
		println('Deployed to $deploy_opt.device_id successfully')
	}
	if deploy_opt.kill_adb {
		cli.kill_adb()
	}
}
