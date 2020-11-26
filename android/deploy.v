// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os

import android.sdk
import android.util

pub struct DeployOptions {
	verbosity	int
	device_id	string
	deploy_file string
	run			string	// Full id 'com.package.name/com.package.name.ActivityName'
	kill_adb	bool	// Kill ADB after use.
}

pub fn device_list() []string {
	return private_device_list(0)
}

fn private_device_list(verbosity int) []string {
	adb := os.join_path(sdk.platform_tools_root(),'adb')
	if !os.is_executable(adb) {
		panic('Couldn\'t locate "adb". Please make sure it\'s installed.')
	}
	adb_list_cmd := [
		adb,
		'devices',
		'-l'
	]
	util.verbosity_print_cmd(adb_list_cmd, verbosity) //opt.verbosity
	output := util.run_or_exit(adb_list_cmd).split('\n')
	mut device_list := []string{}
	for device in output {
		if !device.contains(' model:') { continue }
		device_list << device.all_before(' ')
	}
	return device_list
}

pub fn deploy(opt DeployOptions) bool {

	mut device_id := opt.device_id

	adb := os.join_path(sdk.platform_tools_root(),'adb')
	if !os.is_executable(adb) {
		panic('Couldn\'t locate "adb". Please make sure it\'s installed.')
	}

	devices := private_device_list(opt.verbosity)

	if device_id == 'auto' {
		mut auto_device := ''
		if devices.len > 0 {
			auto_device = devices.first()
		}
		device_id = auto_device

		if device_id == '' {
			eprintln('Couldn\'t find any connected devices.')
		}
	}

	// Deploy
	if device_id != '' {
		if !(device_id in devices) {
			eprintln('Couldn\'t connect to device "${device_id}".')
			return false
		}

		if opt.verbosity > 0 {
			println('Deploying to ${device_id}')
		}

		adb_cmd := [
			adb,
			'-s "${device_id}"',
			'install',
			'-r',
			opt.deploy_file
		]
		util.verbosity_print_cmd(adb_cmd, opt.verbosity)
		util.run_or_exit(adb_cmd)

		if opt.run != '' {
			if opt.verbosity > 0 {
				println('Running "${opt.run}" on ${device_id}')
			}
			adb_run_cmd := [
				adb,
				'-s "${device_id}"',
				'shell',
				'am',
				'start',
				'-n',
				opt.run
			]
			util.verbosity_print_cmd(adb_run_cmd, opt.verbosity)
			util.run_or_exit(adb_run_cmd)
		}

		if opt.kill_adb {
			uos := os.user_os()
			if opt.verbosity > 0 {
				println('Killing adb')
			}
			if uos == 'windows' {
				//os.system('Taskkill /IM adb.exe /F') // TODO Untested
			} else {
				os.system('killall adb')
			}
		}
		return true
	}
	return false
}
