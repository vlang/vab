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
	mut args := arguments()

	// NOTE: `run_vab_sub_command` executes first matching vab sub-command, if found; then `exit(...)`
	cli.run_vab_sub_command(args)

	// Get *potential* input. This allows to support flags from `.vab` files residing next to `input`
	mut input := ''
	if args.len > 1 {
		input = args.last()
		// NOTE: this is to support input as *first* argument. Example: `vab /path/to/code -o /path/to/output.apk`
		if os.is_dir(args[1]) || os.is_file(args[1]) {
			input = args[1]
			args.delete(1) // will otherwise end up in `unmatched_args`
		}
	}

	// Collect user flags precedented going from most implicit to most explicit.
	// Start with defaults -> overwrite by .vab file entries -> overwrite by $VAB_FLAGS -> overwrite by command-line flags.
	mut opt := cli.Options{
		input: input
	}

	opt = cli.options_from_dot_vab(input, opt) or {
		eprintln('Error while parsing `.vab`: ${err}')
		exit(1)
	}

	opt = cli.options_from_env(opt) or {
		eprintln('Error while parsing `VAB_FLAGS`: ${err}')
		eprintln('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	mut unmatched_args := []string{}
	opt, unmatched_args = cli.options_from_arguments(args, opt) or {
		eprintln('Error while parsing `os.args`: ${err}')
		eprintln('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	if unmatched_args.len > 0 {
		eprintln('Error while parsing arguments. Could not match ${unmatched_args}')
		eprintln('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	$if vab_debug_options ? {
		eprintln('--- ${@FN} ---')
		dump(os.args)
		dump(opt)
	}

	if opt.dump_usage {
		documentation := flag.to_doc[cli.Options](cli.vab_documentation_config) or {
			eprintln('Error generating usage documentation via `flag.to_doc[cli.Options](...)` this should not happen.')
			eprintln('Error message: ${err}')
			exit(1)
		}
		println(documentation)
		exit(0)
	}

	if opt.list_ndks {
		if !ndk.found() {
			eprintln('No NDK could be found. Please use `${cli.exe_short_name} doctor` to get more information.')
			exit(1)
		}
		for ndk_v in ndk.versions_available() {
			println(ndk_v)
		}
		exit(0)
	}

	if opt.list_apis {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `${cli.exe_short_name} doctor` to get more information.')
			exit(1)
		}
		for api in sdk.apis_available() {
			println(api)
		}
		exit(0)
	}

	if opt.list_build_tools {
		if !sdk.found() {
			eprintln('No SDK could be found. Please use `${cli.exe_short_name} doctor` to get more information.')
			exit(1)
		}
		for btv in sdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}

	if opt.list_devices {
		devices := android.adb_get_device_list(opt.verbosity) or {
			eprintln('Error getting device list: ${err}')
			exit(1)
		}
		println('Device IDs:\n')
		println(devices.join('\n'))
		exit(0)
	}

	// Call the doctor at this point
	if opt.run_builtin_cmd == 'doctor' {
		// Validate environment
		cli.check_essentials(false)
		opt.resolve(false)
		cli.doctor(opt)
		exit(0)
	}

	// NOTE: All flags after this requires an input argument,
	// *except* doing one-off screenshots on a device:
	if opt.screenshot != '' {
		android.simple_screenshot(
			verbosity: opt.verbosity
			device_id: opt.device_id
			path:      opt.screenshot
			delay:     opt.screenshot_delay
		) or {
			eprintln('Failed to take screenshot:\n${err}')
			exit(1)
		}
		exit(0)
	}

	if opt.run_builtin_cmd == 'install' {
		install_arg := opt.input
		res := env.install(install_arg, opt.verbosity)
		if res == 0 && opt.verbosity > 0 {
			if install_arg != 'auto' {
				println('Installed ${install_arg} successfully.')
			} else {
				println('Installed all dependencies successfully.')
			}
		}
		exit(res)
	}

	// Validate environment
	cli.check_essentials(true)
	opt.resolve(true)

	cli.validate_input(opt.input) or {
		eprintln('${cli.exe_short_name}: ${err}')
		exit(1)
	}

	opt.resolve_output()

	// Validate environment after options and input has been resolved
	opt.validate_env()

	opt.ensure_launch_fields()

	// Keystore file
	keystore := opt.resolve_keystore() or {
		eprintln('${cli.exe_short_name}: could not resolve keystore: ${err}')
		exit(1)
	}

	ado := opt.as_android_deploy_options() or {
		eprintln('Could not create deploy options.\n${err}')
		exit(1)
	}
	deploy_opt := android.DeployOptions{
		...ado
		keystore: keystore
	}

	if opt.verbosity > 1 {
		println('Output will be signed with keystore at "${deploy_opt.keystore.path}"')
	}

	screenshot_opt := opt.as_android_screenshot_options(deploy_opt)

	input_ext := os.file_ext(opt.input)

	// Early deployment of existing packages.
	if input_ext in ['.apk', '.aab'] {
		if deploy_opt.device_id != '' {
			deploy(deploy_opt)
			android.screenshot(screenshot_opt) or {
				eprintln('${cli.exe_short_name} screenshot did not succeed.\n${err}')
				exit(1)
			}
			exit(0)
		}
	}

	aco := opt.as_android_compile_options()
	comp_opt := android.CompileOptions{
		...aco
		cache_key: if os.is_dir(input) || input_ext == '.v' { opt.input } else { '' }
	}
	android.compile(comp_opt) or {
		eprintln('${cli.exe_short_name} compiling didn\'t succeed.\n${err}')
		exit(1)
	}

	apo := opt.as_android_package_options()
	pck_opt := android.PackageOptions{
		...apo
		keystore: keystore
	}
	android.package(pck_opt) or {
		eprintln("Packaging didn't succeed.\n${err}")
		exit(1)
	}

	if deploy_opt.device_id != '' {
		deploy(deploy_opt)
		android.screenshot(screenshot_opt) or {
			eprintln('${cli.exe_short_name} screenshot did not succeed.\n${err}')
			exit(1)
		}
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `${cli.exe_short_name} --device <id> ${os.real_path(opt.output)}` to deploy package')
			println('Use `${cli.exe_short_name} --device <id> run ${os.real_path(opt.output)}` to both deploy and run the package')
			if deploy_opt.run != '' {
				println('Use `adb -s "<DEVICE ID>" shell am start -n "${deploy_opt.run}"` to run the app on the device, via adb')
			}
		}
	}
}

fn deploy(deploy_opt android.DeployOptions) {
	android.deploy(deploy_opt) or {
		eprintln('${cli.exe_short_name} deployment didn\'t succeed.\n${err}')
		if deploy_opt.kill_adb {
			cli.kill_adb()
		}
		exit(1)
	}
	if deploy_opt.verbosity > 0 {
		println('Deployed to ${deploy_opt.device_id} successfully')
	}
	if deploy_opt.kill_adb {
		cli.kill_adb()
	}
}
