// Copyright(C) 2019-2024 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module emulator

import os
import vab.android.util
import vab.android.env
import time

enum ThreadStatus {
	stopped
	running
}

@[noinit]
pub struct Emulator {
pub:
	name string @[required]
	port u16
mut:
	thread_ctrl      thread
	thread_status    ThreadStatus = .stopped
	thread_ctrl_recv chan int
	exe              string
	options          Options
}

@[params]
pub struct Config {
pub:
	port u16 = 5554
}

@[params]
pub struct CameraOptions {
pub:
	front string = 'emulated'
	back  string = 'emulated'
}

@[params]
pub struct SnapshotOptions {
pub:
	name string
	// TODO:
	// -snapstorage <file>            file that contains all state snapshots (default <datadir>/snapshots.img)
	// -no-snapstorage                do not mount a snapshot storage file (this disables all snapshot functionality)
	// -snapshot <name>               name of snapshot within storage file for auto-start and auto-save (default 'default-boot')
	// -no-snapshot                   perform a full boot and do not do not auto-save, but qemu vmload and vmsave operate on snapstorage
	// -no-snapshot-save              do not auto-save to snapshot on exit: abandon changed state
	// -no-snapshot-load              do not auto-start from snapshot: perform a full boot
	// -snapshot-list                 show a list of available snapshots
	// -no-snapshot-update-time       do not do try to correct snapshot time on restore
}

@[params]
pub struct Options {
pub:
	verbosity    int
	wipe_data    bool
	avd          string
	await_boot   bool = true // will wait for the device to boot
	visible      bool // show emulator window on desktop
	metrics      bool // send metrics to Google... default NO
	snapshot     SnapshotOptions
	boot_anim    bool
	camera       CameraOptions
	gpu          string
	acceleration string
}

// verbose prints `msg` to STDOUT if `Options.verbosity` level is >= `verbosity_level`.
pub fn (o &Options) verbose(verbosity_level int, msg string) {
	if o.verbosity >= verbosity_level {
		println(msg)
	}
}

// validate validates the fields of `Options`.
pub fn (o &Options) validate() ! {
	if o.avd == '' {
		return error('${@MOD}.${@STRUCT}.${@FN}: No Android Virtual Device (avd) sat')
	}
	avds := Emulator.list_avds()!
	if o.avd !in avds {
		return error('${@MOD}.${@STRUCT}.${@FN}: Android Virtual Device (avd) "${o.avd}" not found.')
	}
}

// make returns an `Emulator` instance.
pub fn make(config Config) !Emulator {
	if !env.has_emulator() {
		return error('${@MOD}.${@STRUCT}.${@FN}: the `emulator` needs to be installed in the Android SDK. Use `vab install emulator` to install it.')
	}
	if !env.has_avdmanager() {
		// TODO: part of cmdline-tools, should be installed?!
		return error('${@MOD}.${@STRUCT}.${@FN}: `avdmanager` could not be found in the Android SDK.')
	}
	emulator_exe := env.emulator()
	// TODO: call adb to list devices and find a free port if other
	// emulators are running. Give the user a notice if port has to
	// be changed via util.vab_notice()
	mut port := config.port
	return Emulator{
		name: 'emulator-${port}'
		port: port
		exe:  emulator_exe
	}
}

// start starts a new emulator process from a OS monitor thread.
// If `options.await_boot` is `true`, start will block until the
// emulator has fully booted, otherwise it will return immediately.
pub fn (mut e Emulator) start(options Options) ! {
	options.validate()!
	e.options = options
	// start emulator in another process and monitor it in a thread.
	e.thread_status = .running
	e.thread_ctrl = spawn e.run_process(options)
	e.options.verbose(2, 'Emulator thread started')

	if e.options.await_boot {
		e.wait_for_boot()!
	}
}

// has_avd returns `true` if `avd_name` can be found. Use `list_avds` to see all locations of AVD's
pub fn Emulator.has_avd(avd_name string) bool {
	avds := Emulator.list_avds() or { return false }
	return avd_name in avds.keys()
}

// list_avds returns a list of devices detected by running `emulator -list-avds`
// NOTE: for Google reasons, this list can be different from `avdmanager list avd -c`...
pub fn Emulator.list_avds() !map[string]string {
	emulator_exe := env.emulator()
	list_cmd := [emulator_exe, '-list-avds']
	list_res := util.run_or_error(list_cmd)!
	list := list_res.split('\n').filter(it != '').filter(!it.contains(' '))
	mut m := map[string]string{}
	for entry in list {
		m[entry] = entry // TODO: should be a path to the AVD...
	}
	return m
	// TODO: find out how to fix this dumb mess for users
	// if vab_test_avd !in avds {
	// Locating a deterministic location of AVD's has, like so many other Android related things, become a mess.
	// (`avdmanager` can put them in places that the `emulator` does not pickup on the *same* host etc... Typical Google-mess)
	// ... even passing `--path` to `avdmanager` does not work.
	// Here we try a few places and set `ANDROID_AVD_HOME` to make runs a bit more predictable.
	// 	mut avd_home := os.join_path(os.home_dir(), '.android', 'avd')
	// 	eprintln('warning: "${vab_test_avd}" still not in list: ${avds}... trying new location "${avd_home}"')
	// 	os.setenv('ANDROID_AVD_HOME', avd_home, true)
	//
	// 	avds = emulator.Emulator.list_avds() or {
	// 		eprintln('${exe_name} error: ${err}')
	// 		exit(1)
	// 	}
	// 	if vab_test_avd !in avds {
	// 		config_dir := os.config_dir() or {
	// 			eprintln('${exe_name} error: ${err}')
	// 			exit(1)
	// 		}
	// 		avd_home = os.join_path(config_dir, '.android', 'avd')
	// 		eprintln('warning: "${vab_test_avd}" still not in list: ${avds}... trying new location "${avd_home}"')
	// 		os.setenv('ANDROID_AVD_HOME', avd_home, true)
	//
	// 		avds = emulator.Emulator.list_avds() or {
	// 			eprintln('${exe_name} error: ${err}')
	// 			exit(1)
	// 		}
	// 	}
	// }
}

// wait_for_boot blocks execution and waits for the emulator to boot.
// NOTE: this feature is unique to emulator devices.
pub fn (mut e Emulator) wait_for_boot() ! {
	// wait for emulator or fail if emulator thread fails
	adb_look_for_boot_complete_cmd := [
		env.adb(),
		'-s',
		e.name,
		'shell',
		'getprop',
		'dev.bootcomplete',
	]
	e.options.verbose(2, 'Waiting for emulator to be fully booted...')
	for {
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: adb boot check loop.\nRunning: ${adb_look_for_boot_complete_cmd.join(' ')}')
			eprintln('> ${@STRUCT}.${@FN}: running "${adb_look_for_boot_complete_cmd.join(' ')}"...')
		}
		res := os.execute(adb_look_for_boot_complete_cmd.join(' '))
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: adb boot check exit: ${res.exit_code}')
		}
		if res.exit_code == 0 {
			break
		}
		time.sleep(1000 * time.millisecond)
		if e.thread_status != .running {
			$if debug {
				eprintln('> ${@STRUCT}.${@FN}: waiting for thread to close')
			}
			e.thread_ctrl.wait()
			return error('${@MOD}.${@STRUCT}.${@FN}: emulator thread not running')
		}
	}
}

// stop stops the emulator thread and emulator child process if they are running.
pub fn (mut e Emulator) stop() {
	e.options.verbose(1, 'Stopping emulator...')
	if !e.thread_ctrl_recv.closed {
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: asking emulator to gracefully shutdown...')
		}
		e.thread_ctrl_recv <- 1 // ask for graceful exit
	}
	$if debug {
		eprintln('> ${@STRUCT}.${@FN}: waiting for emulator thread exit...')
	}
	if e.thread_status != .running {
		e.thread_ctrl.wait()
	}
	e.options.verbose(1, 'Emulator is now stopped')
}

// run_process runs the `emulator` and starts monitoring it.
// run_process can be started with `spawn` so it is non-blocking.
// If started with `spawn` action codes can be sent via the `thread_ctrl_recv` channel.
// NOTE: `e.thread_status` should be *read* everywhere else except in this function.
fn (mut e Emulator) run_process(options Options) {
	mut emulator_args := [
		'-avd',
		e.options.avd,
		'-port',
		'${e.port}', // defines the adb device name. E.g.: "emulator-5554"
	]
	if e.options.wipe_data {
		emulator_args << '-wipe-data'
	}
	if !e.options.metrics {
		emulator_args << '-no-metrics'
	}
	if e.options.snapshot.name == '' {
		emulator_args << '-no-snapshot'
	}
	if !e.options.visible {
		emulator_args << '-no-window'
	}
	if !e.options.boot_anim {
		emulator_args << '-no-boot-anim'
	}
	if e.options.gpu != '' {
		emulator_args << '-gpu'
		emulator_args << e.options.gpu
	}
	if e.options.acceleration != '' {
		emulator_args << '-accel'
		emulator_args << e.options.acceleration
	}
	emulator_args << '-camera-front'
	emulator_args << e.options.camera.front
	emulator_args << '-camera-back'
	emulator_args << e.options.camera.back

	e.options.verbose(1, 'Starting emulator...')
	if e.options.verbosity > 0 {
		mut emulator_args_verbose := [e.exe]
		emulator_args_verbose << emulator_args
		util.verbosity_print_cmd(emulator_args_verbose, e.options.verbosity)
	}
	mut p := os.new_process(e.exe)
	p.set_args(emulator_args)
	p.set_redirect_stdio()
	p.run()
	mut action := 0
	for {
		if !p.is_alive() {
			action = 2
			e.options.verbose(3, 'Emulator process not alive anymore')
			stdout := p.stdout_slurp()
			stderr := p.stderr_slurp()
			println(stdout)
			eprintln(stderr)
			e.thread_status = .stopped
			$if debug {
				eprintln('> ${@STRUCT}.${@FN}: waiting for process; action: "${action}" status: "${p.status}"')
			}
			p.wait()
			break
		}
		if e.thread_ctrl_recv.try_pop(mut action) == .success {
			if action != 0 {
				if action == 1 {
					$if debug {
						eprintln('> ${@STRUCT}.${@FN}: sending SIGTERM to process; action: "${action}" status: "${p.status}"')
					}
					p.signal_term()
					$if debug {
						eprintln('> ${@STRUCT}.${@FN}: waiting for process; action: "${action}" status: "${p.status}"')
					}
					p.wait()
				}
				e.options.verbose(2, 'Emulator process terminating on request')
				$if debug {
					eprintln('> ${@STRUCT}.${@FN}: breaking; action: "${action}" status: "${p.status}"')
				}
				break
			}
		}
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: thread reading; action: "${action}" status: "${p.status}"')
		}
		time.sleep(1000 * time.millisecond)
	}
	if action != 1 {
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: thread BAD status; action: "${action}" status: "${p.status}"')
		}
	} else {
		$if debug {
			eprintln('> ${@STRUCT}.${@FN}: thread OK status; action: "${action}" status: "${p.status}"')
		}
	}
	e.thread_status = .stopped
	e.thread_ctrl_recv.close()
	p.close()
	e.options.verbose(2, 'Exiting emulator thread')
}
