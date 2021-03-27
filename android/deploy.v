// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import java
import android.env
import android.util

pub struct DeployOptions {
	verbosity   int
	v_flags     []string
	format      PackageFormat = .apk
	keystore    Keystore
	work_dir    string
	device_id   string
	device_log  bool
	log_mode    LogMode = .filtered
	deploy_file string
	log_tag     string
	run         string // Full id 'com.package.name/com.package.name.ActivityName'
	kill_adb    bool   // Kill ADB after use.
}

pub enum LogMode {
	filtered
	raw
}

pub fn device_list() []string {
	return get_device_list(0)
}

fn get_device_list(verbosity int) []string {
	adb := env.adb()
	if !os.is_executable(adb) {
		panic('Couldn\'t locate "adb". Please make sure it\'s installed.')
	}
	adb_list_cmd := [
		adb,
		'devices',
		'-l',
	]
	util.verbosity_print_cmd(adb_list_cmd, verbosity) // opt.verbosity
	output := util.run_or_exit(adb_list_cmd).split('\n')
	mut device_list := []string{}
	for device in output {
		if !device.contains(' model:') {
			continue
		}
		device_list << device.all_before(' ')
	}
	return device_list
}

pub fn deploy(opt DeployOptions) bool {
	return match opt.format {
		.apk {
			deploy_apk(opt)
		}
		.aab {
			deploy_aab(opt)
		}
	}
}

pub fn deploy_apk(opt DeployOptions) bool {
	mut device_id := opt.device_id

	adb := env.adb()
	if !os.is_executable(adb) {
		panic('Couldn\'t locate "adb". Please make sure it\'s installed.')
	}

	devices := get_device_list(opt.verbosity)

	if device_id == 'auto' {
		mut auto_device := ''
		if devices.len > 0 {
			auto_device = devices.first()
		}
		device_id = auto_device

		if device_id == '' {
			eprintln("Couldn't find any connected devices.")
		}
	}
	// Deploy
	if device_id != '' {
		if !(device_id in devices) {
			eprintln('Couldn\'t connect to device "$device_id".')
			return false
		}

		if opt.verbosity > 0 {
			println('Deploying $opt.format package to "$device_id"')
		}

		adb_logcat_clear_cmd := [
			adb,
			'-s "$device_id"',
			'logcat',
			'-c',
		]
		if opt.run != '' && opt.device_log {
			// Clear logs first
			if opt.verbosity > 0 {
				println('Clearing log buffer on device "$device_id"')
			}
			util.verbosity_print_cmd(adb_logcat_clear_cmd, opt.verbosity)
			util.run_or_exit(adb_logcat_clear_cmd)
		}

		adb_cmd := [
			adb,
			'-s "$device_id"',
			'install',
			'-r',
			opt.deploy_file,
		]
		util.verbosity_print_cmd(adb_cmd, opt.verbosity)
		util.run_or_exit(adb_cmd)

		if opt.run != '' {
			if opt.verbosity > 0 {
				println('Running "$opt.run" on "$device_id"')
			}
			adb_run_cmd := [
				adb,
				'-s "$device_id"',
				'shell',
				'am',
				'start',
				'-n',
				opt.run,
			]
			util.verbosity_print_cmd(adb_run_cmd, opt.verbosity)
			util.run_or_exit(adb_run_cmd)
		}

		mut crash_mode := false
		if opt.device_log {
			if opt.verbosity > 0 {
				println('Showing log output from device "$device_id"')
			}
			println('Ctrl+C to cancel logging')
			mut adb_logcat_cmd := [
				adb,
				'-s',
				'$device_id',
				'logcat',
			]

			// Only filter output in "normal" log mode
			if opt.log_mode == .filtered {
				// Sokol
				is_debug := '-cg' in opt.v_flags || '-g' in opt.v_flags
				if is_debug {
					adb_logcat_cmd << 'SOKOL_APP:D'
				}
				adb_logcat_cmd << [
					'V_ANDROID:D',
					'$opt.log_tag:D',
					'System.err:D',
				]
				// if !is_debug {
				adb_logcat_cmd << '*:S'
			}

			// log_cmd := adb_logcat_cmd.join(' ')
			// println('Use "$log_cmd" to view logs...')
			util.verbosity_print_cmd(adb_logcat_cmd, opt.verbosity)
			mut p := os.new_process(adb_logcat_cmd[0])
			p.set_args(adb_logcat_cmd[1..])
			p.set_redirect_stdio()
			p.run()
			for p.is_alive() {
				s, b := os.fd_read(p.stdio_fd[1], 2 * 4096)
				if s.contains('beginning of crash') {
					crash_mode = true
					break
				}
				if b <= 0 {
					break
				}
				print('$s')
				os.flush()
			}
			if !crash_mode {
				rest := p.stdout_slurp()
				p.wait()
				println('$rest')
			}
		}

		adb_logcat_cmd := [
			adb,
			'-s',
			'$device_id',
			'logcat',
			'--buffer=crash',
			'-d',
		]
		util.verbosity_print_cmd(adb_logcat_cmd, opt.verbosity)
		crash_log := util.run_or_exit(adb_logcat_cmd)
		if crash_log.count('\n') > 3 {
			eprintln('It looks like your app might have crashed\nDumping crash buffer:')
			eprintln(crash_log)
			eprintln('You can clear all logs by running:\n"' + adb_logcat_clear_cmd.join(' ') + '"')
		}

		if opt.kill_adb {
			uos := os.user_os()
			if opt.verbosity > 0 {
				println('Killing adb')
			}
			if uos == 'windows' {
				// os.system('Taskkill /IM adb.exe /F') // TODO Untested
			} else {
				os.system('killall adb')
			}
		}
		return true
	}
	return false
}

pub fn deploy_aab(opt DeployOptions) bool {
	mut device_id := opt.device_id

	adb := env.adb()
	java_exe := os.join_path(java.jre_bin_path(), 'java')
	bundletool := env.bundletool() // Run with "java -jar ..."

	if !os.is_executable(adb) {
		panic('Couldn\'t locate "adb". Please make sure it\'s installed.')
	}

	devices := get_device_list(opt.verbosity)

	if device_id == 'auto' {
		mut auto_device := ''
		if devices.len > 0 {
			auto_device = devices.first()
		}
		device_id = auto_device

		if device_id == '' {
			eprintln("Couldn't find any connected devices.")
		}
	}
	// Deploy
	if device_id != '' {
		if opt.verbosity > 0 {
			println('Building APKs from "$opt.deploy_file"')
		}

		apks_path := os.join_path(opt.work_dir, 
			os.file_name(opt.deploy_file).all_before_last('.') + '.apks')
		keystore := resolve_keystore(opt.keystore, opt.verbosity)

		os.rm(apks_path) or {}

		// java -jar bundletool.jar build-apks --bundle=/MyApp/my_app.aab --output=/MyApp/my_app.apks --ks=/MyApp/keystore.jks --ks-pass=file:/MyApp/keystore.pwd --ks-key-alias=MyKeyAlias --key-pass=file:/MyApp/key.pwd
		bundletool_apks_cmd := [
			java_exe,
			'-jar',
			bundletool,
			'build-apks',
			'--bundle="' + opt.deploy_file + '"',
			'--output="' + apks_path + '"',
			'--ks="' + keystore.path + '"',
			'--ks-pass=pass:' + keystore.password,
			'--ks-key-alias="' + keystore.alias + '"',
			'--key-pass=pass:' + keystore.alias_password,
		]
		util.verbosity_print_cmd(bundletool_apks_cmd, opt.verbosity)
		util.run_or_exit(bundletool_apks_cmd)

		if !(device_id in devices) {
			eprintln('Couldn\'t connect to device "$device_id".')
			return false
		}

		if opt.verbosity > 0 {
			println('Deploying $opt.format package to "$device_id"')
		}

		adb_logcat_clear_cmd := [
			adb,
			'-s "$device_id"',
			'logcat',
			'-c',
		]
		if opt.run != '' && opt.device_log {
			// Clear logs first
			if opt.verbosity > 0 {
				println('Clearing log buffer on device "$device_id"')
			}
			util.verbosity_print_cmd(adb_logcat_clear_cmd, opt.verbosity)
			util.run_or_exit(adb_logcat_clear_cmd)
		}
		// java -jar bundletool.jar install-apks --apks=/MyApp/my_app.apks
		bundletool_install_apks_cmd := [
			java_exe,
			'-jar',
			bundletool,
			'install-apks',
			'--apks="' + apks_path + '"',
		]
		util.verbosity_print_cmd(bundletool_install_apks_cmd, opt.verbosity)
		util.run_or_exit(bundletool_install_apks_cmd)

		/*
		adb_cmd := [
			adb,
			'-s "$device_id"',
			'install',
			'-r',
			opt.deploy_file,
		]
		util.verbosity_print_cmd(adb_cmd, opt.verbosity)
		util.run_or_exit(adb_cmd)
		*/

		if opt.run != '' {
			if opt.verbosity > 0 {
				println('Running "$opt.run" on "$device_id"')
			}
			adb_run_cmd := [
				adb,
				'-s "$device_id"',
				'shell',
				'am',
				'start',
				'-n',
				opt.run,
			]
			util.verbosity_print_cmd(adb_run_cmd, opt.verbosity)
			util.run_or_exit(adb_run_cmd)
		}

		mut crash_mode := false
		if opt.device_log {
			if opt.verbosity > 0 {
				println('Showing log output from device "$device_id"')
			}
			println('Ctrl+C to cancel logging')
			mut adb_logcat_cmd := [
				adb,
				'-s',
				'$device_id',
				'logcat',
			]
			// Sokol
			is_debug := '-cg' in opt.v_flags || '-g' in opt.v_flags
			if is_debug {
				adb_logcat_cmd << 'SOKOL_APP:D'
			}
			adb_logcat_cmd << [
				'V_ANDROID:D',
				'$opt.log_tag:D',
				'System.out:D',
				'System.err:D',
			]
			// if !is_debug {
			adb_logcat_cmd << '*:S'
			//}

			// log_cmd := adb_logcat_cmd.join(' ')
			// println('Use "$log_cmd" to view logs...')
			util.verbosity_print_cmd(adb_logcat_cmd, opt.verbosity)
			mut p := os.new_process(adb_logcat_cmd[0])
			p.set_args(adb_logcat_cmd[1..])
			p.set_redirect_stdio()
			p.run()
			for p.is_alive() {
				s, b := os.fd_read(p.stdio_fd[1], 2 * 4096)
				if s.contains('beginning of crash') {
					crash_mode = true
					break
				}
				if b <= 0 {
					break
				}
				print('$s')
				os.flush()
			}
			if !crash_mode {
				rest := p.stdout_slurp()
				p.wait()
				println('$rest')
			}
		}

		adb_logcat_cmd := [
			adb,
			'-s',
			'$device_id',
			'logcat',
			'--buffer=crash',
			'-d',
		]
		util.verbosity_print_cmd(adb_logcat_cmd, opt.verbosity)
		crash_log := util.run_or_exit(adb_logcat_cmd)
		if crash_log.count('\n') > 3 {
			eprintln('It looks like your app might have crashed\nDumping crash buffer:')
			eprintln(crash_log)
			eprintln('You can clear all logs by running:\n"' + adb_logcat_clear_cmd.join(' ') + '"')
		}

		if opt.kill_adb {
			uos := os.user_os()
			if opt.verbosity > 0 {
				println('Killing adb')
			}
			if uos == 'windows' {
				// os.system('Taskkill /IM adb.exe /F') // TODO Untested
			} else {
				os.system('killall adb')
			}
		}
		return true
	}
	return false
}
