// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import time
import vab.java
import vab.util as vabutil
import vab.android.env
import vab.android.util

pub struct DeployOptions {
pub:
	verbosity        int
	v_flags          []string
	format           PackageFormat = .apk
	keystore         Keystore
	activity_name    string
	work_dir         string
	device_id        string
	device_log       bool
	log_mode         LogMode = .filtered
	clear_device_log bool
	deploy_file      string
	log_tags         []string
	run              string // Full id 'com.package.name/com.package.name.ActivityName'
	kill_adb         bool   // Kill ADB after use.
}

pub enum LogMode {
	filtered
	raw
}

// verbose prints `msg` to STDOUT if `DeployOptions.verbosity` level is >= `verbosity_level`.
pub fn (do &DeployOptions) verbose(verbosity_level int, msg string) {
	if do.verbosity >= verbosity_level {
		println(msg)
	}
}

fn (do DeployOptions) gen_logcat_filters() []string {
	mut filters := []string{}
	// Only filter output in "normal" log mode
	if do.log_mode == .filtered {
		is_debug_build := '-cg' in do.v_flags || '-g' in do.v_flags
		if is_debug_build {
			// Sokol
			filters << 'SOKOL_APP:V'
			// Boehm-Demers-Weiser Garbage Collector (bdwgc / libgc)
			filters << 'BDWGC:V'
		}
		// Include caller log tags
		for log_tag in do.log_tags {
			mut tag := log_tag
			if !tag.contains(':') {
				tag += ':V'
			}
			filters << '${tag}'
		}
		filters << [
			'V:V',
			// 'System.out:D', // Used by many other Android libs - so it's noisy
			// 'System.err:D',
			'${do.activity_name}:V',
		]
		// if !is_debug_build {
		filters << '*:S'
	}
	return filters
}

pub fn deploy(opt DeployOptions) ! {
	match opt.format {
		.apk {
			deploy_apk(opt)!
		}
		.aab {
			deploy_aab(opt)!
		}
	}
}

pub fn deploy_apk(opt DeployOptions) ! {
	error_tag := @MOD + '.' + @FN

	if !env.has_adb() {
		return error('${error_tag}: Could not locate "adb". Please make sure it is installed.')
	}
	adb := env.adb()

	mut device_id := ensure_device_id(opt.device_id, opt.verbosity) or {
		return error('${error_tag}:\n${err}')
	}

	// Deploy
	if device_id != '' {
		opt.verbose(1, 'Deploying ${opt.format} package to "${device_id}"')
		if opt.kill_adb {
			os.signal_opt(.int, kill_adb_on_exit) or {
				// Kept for debugging return error('$error_tag: Could not set signal handler:\n$err')
			}
		}

		adb_cmd := [
			adb,
			'-s "${device_id}"',
			'install',
			'-r',
			opt.deploy_file,
		]
		util.verbosity_print_cmd(adb_cmd, opt.verbosity)
		util.run_or_error(adb_cmd)!

		// Clearing the logs should be done *after* install so there is actually
		// something in the logs to clear - otherwise the clear command might fail,
		// presumably because of low log activity. It seem to happen more often on
		// devices with low log activity (like the slim `aosp_atd` emulator images).
		adb_logcat_clear_cmd := [
			adb,
			'-s "${device_id}"',
			'logcat',
			'-c',
		]
		if opt.clear_device_log || (opt.run != '' && opt.device_log) {
			// Give adb/Android/connection time to settle... *sigh*
			time.sleep(150 * time.millisecond)
			// Clear logs first
			opt.verbose(1, 'Clearing log buffer on device "${device_id}"...')
			util.verbosity_print_cmd(adb_logcat_clear_cmd, opt.verbosity)
			util.run_or_error(adb_logcat_clear_cmd)!
		}
		// Give adb/Android/connection time to settle... *sigh*
		time.sleep(150 * time.millisecond)

		if opt.run != '' {
			opt.verbose(1, 'Running "${opt.run}" on "${device_id}"...')
			adb_run_cmd := [
				adb,
				'-s "${device_id}"',
				'shell',
				'am',
				'start',
				'-n',
				opt.run,
			]
			util.verbosity_print_cmd(adb_run_cmd, opt.verbosity)
			util.run_or_error(adb_run_cmd)!
		}

		if opt.device_log {
			adb_log_step(opt, device_id)!
		}

		has_crash_report := adb_detect_and_report_crashes(opt, device_id)!
		if has_crash_report {
			vabutil.vab_notice('You can clear all logs by running:\n"' +
				adb_logcat_clear_cmd.join(' ') + '"')
		}
	}
}

pub fn deploy_aab(opt DeployOptions) ! {
	error_tag := @MOD + '.' + @FN
	if !env.has_adb() {
		return error('${error_tag}: Could not locate "adb". Please make sure it is installed.')
	}
	adb := env.adb()

	mut device_id := ensure_device_id(opt.device_id, opt.verbosity) or {
		return error('${error_tag}:\n${err}')
	}

	java_exe := os.join_path(java.jre_bin_path(), 'java')
	bundletool := env.bundletool() // Run with "java -jar ..."

	// Deploy
	if device_id != '' {
		opt.verbose(1, 'Building APKs from "${opt.deploy_file}"...')

		apks_path := os.join_path(opt.work_dir,
			os.file_name(opt.deploy_file).all_before_last('.') + '.apks')
		keystore := resolve_keystore(opt.keystore)!

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
		util.run_or_error(bundletool_apks_cmd)!

		opt.verbose(1, 'Deploying ${opt.format} package to "${device_id}"...')

		if opt.kill_adb {
			os.signal_opt(.int, kill_adb_on_exit) or {
				// Kept for debugging return error('$error_tag: Could not set signal handler:\n$err')
			}
		}

		// java -jar bundletool.jar install-apks --apks=/MyApp/my_app.apks
		bundletool_install_apks_cmd := [
			java_exe,
			'-jar',
			bundletool,
			'install-apks',
			'--device-id ${device_id}',
			'--apks="' + apks_path + '"',
		]
		util.verbosity_print_cmd(bundletool_install_apks_cmd, opt.verbosity)
		util.run_or_error(bundletool_install_apks_cmd)!

		// Clearing the logs should be done *after* install so there is actually
		// something in the logs to clear - otherwise the clear command might fail,
		// presumably because of low log activity. It seem to happen more often on
		// devices with low log activity (like the slim `aosp_atd` emulator images).
		adb_logcat_clear_cmd := [
			adb,
			'-s "${device_id}"',
			'logcat',
			'-c',
		]
		if opt.clear_device_log || (opt.run != '' && opt.device_log) {
			// Give adb/Android/connection time to settle... *sigh*
			time.sleep(150 * time.millisecond)
			// Clear logs first
			opt.verbose(1, 'Clearing log buffer on device "${device_id}"...')
			util.verbosity_print_cmd(adb_logcat_clear_cmd, opt.verbosity)
			util.run_or_error(adb_logcat_clear_cmd)!
		}

		// Give adb/Android/connection time to settle... *sigh*
		time.sleep(150 * time.millisecond)

		if opt.run != '' {
			if opt.verbosity > 0 {
				println('Running "${opt.run}" on "${device_id}"')
			}
			adb_run_cmd := [
				adb,
				'-s "${device_id}"',
				'shell',
				'am',
				'start',
				'-n',
				opt.run,
			]
			util.verbosity_print_cmd(adb_run_cmd, opt.verbosity)
			util.run_or_error(adb_run_cmd)!
		}

		if opt.device_log {
			adb_log_step(opt, device_id)!
		}

		has_crash_report := adb_detect_and_report_crashes(opt, device_id)!
		if has_crash_report {
			vabutil.vab_notice('You can clear all logs by running:\n"' +
				adb_logcat_clear_cmd.join(' ') + '"')
		}
	}
}

fn adb_detect_and_report_crashes(opt DeployOptions, device_id string) !bool {
	adb := env.adb()
	time.sleep(150 * time.millisecond)
	adb_logcat_cmd := [
		adb,
		'-s',
		'${device_id}',
		'logcat',
		'--buffer=crash',
		'-d',
	]
	util.verbosity_print_cmd(adb_logcat_cmd, opt.verbosity)
	crash_log := util.run_or_error(adb_logcat_cmd)!
	if crash_log.count('\n') > 3 {
		vabutil.vab_notice('It looks like your app might have crashed. Dumping crash buffer...',
			details: crash_log
		)
		vabutil.vab_notice('The above crash log(s) may be old and/or unrelated to this run')
		vabutil.vab_notice('Use `--log-clear` to clear the device logs prior to installs and app launches')
		return true
	}
	return false
}

fn adb_log_step(opt DeployOptions, device_id string) ! {
	adb := env.adb()
	mut crash_mode := false
	opt.verbose(1, 'Showing log output from device "${device_id}"')
	println('Ctrl+C to cancel logging')
	mut adb_logcat_cmd := [
		adb,
		'-s',
		'${device_id}',
		'logcat',
	]

	adb_logcat_cmd << opt.gen_logcat_filters()

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
		print('${s}')
		os.flush()
	}
	if !crash_mode {
		rest := p.stdout_slurp()
		p.wait()
		println('${rest}')
	}
}

fn kill_adb_on_exit(signum os.Signal) {
	uos := os.user_os()
	vabutil.vab_notice('Killing adb on signal ${signum}')
	if uos == 'windows' {
		// os.system('Taskkill /IM adb.exe /F') // TODO Untested
	} else {
		os.system('killall adb')
	}
}
