// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import time
import vab.paths
import vab.android.env
import vab.android.util

@[params]
pub struct SimpleScreenshotOptions {
pub:
	verbosity int
	device_id string
	path      string // /path/to/screenshot.png
	delay     f64    // delay this many seconds before taking the shot
}

pub struct ScreenshotOptions {
pub:
	deploy_options DeployOptions // This should be copy of the deploy options used to deploy the app
	path           string        // /path/to/screenshot.png
	delay          f64           // delay this many seconds before taking the shot
	on_log         string
	on_log_timeout f64 // Values <= 0 means no timeout
}

fn resolve_screenshot_output(input string) !(string, string) {
	mut out_file := os.file_name(input)
	mut out_dir := input.trim_string_right(os.path_separator)
	if out_file.ends_with('.png') {
		out_dir = os.dir(out_dir)
	} else if os.is_dir(out_dir) {
		date := time.now()
		date_str := date.format_ss_milli().replace_each([' ', '', '.', '', '-', '', ':', ''])
		shot_filename := os.join_path('${date_str}.png')
		out_file = shot_filename
	}
	return out_dir, out_file
}

// resolve_output returns the resolved output directory path and the filename.
pub fn (so ScreenshotOptions) resolve_output() !(string, string) {
	return resolve_screenshot_output(so.path)
}

pub fn simple_screenshot(opt SimpleScreenshotOptions) ! {
	do_screenshot := opt.path != ''
	if !do_screenshot {
		return
	}

	device_id := ensure_device_id(opt.device_id, opt.verbosity) or {
		return error('${@MOD}.${@FN}:\n${err}')
	}
	// Screenshot requested, but no device has been set
	if do_screenshot && device_id == '' {
		return error('${@MOD}.${@FN}: Taking screenshots requires a device id. Set one via --device or ANDROID_SERIAL')
	}
	out_dir, out_file := resolve_screenshot_output(opt.path)!
	paths.ensure(out_dir)!

	output := os.join_path(out_dir, out_file)

	enable_delay := opt.delay > 0
	if enable_delay {
		if opt.verbosity > 1 {
			println('Sleeping ${opt.delay:.2f} seconds before screenshot...')
		}
		time.sleep(opt.delay * time.second)
	}

	// Do a one-off screenshot
	if opt.verbosity > 0 {
		println('Taking screenshot to "${output}"')
	}
	adb_screenshot(device_id, output)!
}

// screenshot takes a screenshot on a device and save it on the host machine.
pub fn screenshot(opt ScreenshotOptions) ! {
	do_screenshot := opt.path != ''
	if !do_screenshot {
		return
	}

	deploy_opt := opt.deploy_options
	verbosity := deploy_opt.verbosity

	device_id := ensure_device_id(deploy_opt.device_id, deploy_opt.verbosity) or {
		return error('${@MOD}.${@FN}:\n${err}')
	}
	// Screenshot requested, but no device has been set
	if do_screenshot && device_id == '' {
		return error('${@MOD}.${@FN}: Taking screenshots requires a device id. Set one via --device or ANDROID_SERIAL')
	}

	out_dir, out_file := opt.resolve_output()!
	paths.ensure(out_dir)!

	output := os.join_path(out_dir, out_file)
	if os.exists(output) {
		return error('${@MOD}.${@FN}: output file "${output}" already exists')
	}

	do_screenshot_on_log_line := opt.on_log != ''
	enable_delay := opt.delay > 0

	if enable_delay {
		if verbosity > 1 {
			println('Sleeping ${opt.delay:.2f} seconds before screenshot...')
		}
		time.sleep(opt.delay * time.second)
	}
	if !do_screenshot_on_log_line {
		// Do a one-off screenshot
		if verbosity > 0 {
			println('Taking screenshot to "${output}"')
		}
		adb_screenshot(device_id, output)!
	} else {
		// Adelay a specified log line to appear
		screenshot_on_log_line(opt)!
	}
}

enum ScreenshotLogExitReason {
	ok
	error
	crash
	search_string_found
	timeout
}

// screenshot_on_log_line takes a screenshot when a specified string
// appears in the Android log output.
pub fn screenshot_on_log_line(opt ScreenshotOptions) ! {
	do_screenshot := opt.path != ''
	if !do_screenshot {
		return
	}

	deploy_opt := opt.deploy_options
	verbosity := deploy_opt.verbosity

	device_id := ensure_device_id(deploy_opt.device_id, deploy_opt.verbosity) or {
		return error('${@MOD}.${@FN}:\n${err}')
	}
	// Screenshot requested, but no device has been set
	if do_screenshot && device_id == '' {
		return error('${@MOD}.${@FN}: Taking screenshots requires a device id. Set one via --device or ANDROID_SERIAL')
	}

	out_dir, out_file := opt.resolve_output()!
	paths.ensure(out_dir)!

	output := os.join_path(out_dir, out_file)
	if os.exists(output) {
		return error('${@MOD}.${@FN}: output file "${output}" already exists')
	}

	enable_delay := opt.delay > 0
	enable_timeout := opt.on_log_timeout > 0

	if !env.has_adb() {
		return error('${@MOD}.${@FN}: Could not locate "adb". Please make sure it is installed.')
	}
	adb := env.adb()

	mut adb_logcat_cmd := [
		adb,
		'-s',
		'${device_id}',
		'logcat',
		'-d',
	]

	adb_logcat_cmd << deploy_opt.gen_logcat_filters()

	if enable_delay {
		if verbosity > 1 {
			println('Sleeping ${opt.delay:.2f} seconds before screenshot...')
		}
		time.sleep(opt.delay * time.second)
	}
	if verbosity > 0 {
		println('Monitoring log output for "${opt.on_log}" on device "${device_id}"')
	}
	if !enable_timeout {
		println('Ctrl+C to exit in case the screenshot is never taken')
	} else {
		if verbosity > 1 {
			println('The screenshot attempt will timeout after ${opt.on_log_timeout} seconds')
		}
	}

	mut exit_mode := ScreenshotLogExitReason.ok

	util.verbosity_print_cmd(adb_logcat_cmd, verbosity)

	mut log_lines := ''
	mut timeout_watch := time.new_stopwatch()
	for {
		log_lines = util.run_or_error(adb_logcat_cmd) or {
			exit_mode = .crash
			break
		}
		if log_lines.contains('beginning of crash') {
			exit_mode = .crash
			break
		}
		if log_lines.contains(opt.on_log) {
			exit_mode = .search_string_found
			break
		}
		if enable_timeout {
			elapsed := timeout_watch.elapsed().seconds()
			timeout := opt.on_log_timeout
			if elapsed >= timeout {
				exit_mode = .timeout
				break
			}
		}
		time.sleep(64 * time.millisecond)
	}
	if exit_mode in [.ok, .search_string_found] {
		if verbosity > 0 {
			println('Taking screenshot to "${output}"')
		}
		adb_screenshot(device_id, output)!
	} else {
		match exit_mode {
			.crash {
				return error('${@MOD}.${@FN}: taking screenshot failed because the application crashed. Log lines:\n${log_lines}')
			}
			.error {
				return error('${@MOD}.${@FN}: taking screenshot failed because running adb failed. Log lines:\n${log_lines}')
			}
			.timeout {
				return error('${@MOD}.${@FN}: taking screenshot failed because the timeout (${opt.on_log_timeout}) was reached. Log lines:\n${log_lines}')
			}
			else {
				return error('${@MOD}.${@FN}: taking screenshot failed for unknown reasons. Log lines:\n${log_lines}')
			}
		}
	}
}
