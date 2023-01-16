// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import time
import vab.android.util
import vab.android.env

// adb_get_device_list returns a list of Android devices available on the system.
pub fn adb_get_device_list(verbosity int) ![]string {
	error_tag := '${@MOD}.${@FN}'
	if !env.has_adb() {
		return error('${error_tag}: Could not locate "adb". Please make sure it is installed.')
	}
	adb := env.adb()

	adb_list_cmd := [
		adb,
		'devices',
		'-l',
	]
	util.verbosity_print_cmd(adb_list_cmd, verbosity) // opt.verbosity
	output := util.run_or_error(adb_list_cmd)!
	mut device_list := []string{}
	for device in output.split('\n') {
		if !device.contains(' model:') {
			continue
		}
		device_list << device.all_before(' ')
	}
	return device_list
}

// adb_log_dump returns the log output by running `adb -s <device id> logcat -d`
pub fn adb_log_dump(device_id string, verbosity int) !string {
	adb := env.adb()
	time.sleep(150 * time.millisecond)
	adb_logcat_cmd := [
		adb,
		'-s',
		'${device_id}',
		'logcat',
		'-d',
	]
	util.verbosity_print_cmd(adb_logcat_cmd, verbosity)
	log_dump := util.run_or_error(adb_logcat_cmd)!
	return log_dump
}

// adb_screenshot takes a screenshot of `device_id` and save it to `outfile`.
// Currently only .png files are supported.
pub fn adb_screenshot(device_id string, out_file string) ! {
	if !out_file.ends_with('.png') {
		return error('${@MOD}.${@FN}: only .png files are supported when taking screenshots')
	}
	if os.exists(out_file) {
		return error('${@MOD}.${@FN}: ${out_file} already exists')
	}
	adb := env.adb()
	// adb exec-out screencap -p > screen.png
	// From: https://stackoverflow.com/a/37191719/1904615
	mut adb_screenshot_cmd := [
		adb,
		'-s',
		'${device_id}',
		'exec-out',
		'screencap -p',
		'> ${out_file}',
	]
	util.run_or_error(adb_screenshot_cmd)!
}

// device_list returns a list of connected Android devices.s
pub fn device_list() []string {
	return adb_get_device_list(0) or { return []string{} }
}

// ensure_device_id ensures that the device with `id` is available, and connected.
// If `'auto'` is passed as `id` ensure_device_id will return the first available device.
pub fn ensure_device_id(id string, verbosity int) !string {
	error_tag := '${@MOD}.${@FN}'
	if !env.has_adb() {
		return error('${error_tag}: Could not locate "adb". Please make sure it is installed.')
	}
	mut device_id := id

	devices := adb_get_device_list(verbosity) or {
		return error('${error_tag}: Failed getting device list:\n${err}')
	}

	if device_id == 'auto' {
		mut auto_device := ''
		if devices.len > 0 {
			auto_device = devices.first()
		}
		device_id = auto_device

		if device_id == '' {
			return error('${error_tag}: Could not find any connected devices.')
		}
	}

	if device_id != '' {
		// Do this check in case the device was *not* auto-detected
		if device_id !in devices {
			return error('${error_tag}: Could not locate device "${device_id}" in device list.')
		}
		return device_id
	}
	return error('${error_tag}: Could not ensure device id "${device_id}".')
}
