// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module main

import os
import vab.vxt
import vab.vabxt

const exe_name = os.file_name(os.executable())
const exe_dir = os.dir(os.real_path(os.executable()))

fn main() {
	do_runtime_tests()
}

pub fn run(args []string) os.Result {
	cmd := args.join(' ')
	eprintln('${exe_name} running: ${cmd}')
	return os.execute(cmd)
}

fn do_runtime_tests() {
	mut errors := []string{}

	v_exe := vxt.vexe()
	assert v_exe != '', 'V needs to be installed and working'
	vab_exe := vabxt.vabexe()
	assert vab_exe != '', 'vab needs to be fully installed and working'
	vab_home := vabxt.home()
	assert vab_home != ''

	runtime_tests := os.walk_ext(os.join_path(vab_home, 'tests', 'at-runtime'), '.vv')
	assert runtime_tests.len > 0, 'There should be at least 1 test'
	for runtime_test in runtime_tests {
		res := run([v_exe, 'run', runtime_test])
		if res.exit_code != 0 {
			eprintln(res.output)
			exit(1)
		}
	}
}
