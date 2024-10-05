// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module main

import os
import vab.vxt
import vab.vabxt

const exe_name = os.file_name(os.executable())
const exe_dir = os.dir(os.real_path(os.executable()))

fn main() {
	v_test_all()
}

fn run(args []string) os.Result {
	cmd := args.join(' ')
	eprintln('${exe_name} running: ${cmd}')
	return os.execute(cmd)
}

fn v_test_all() {
	mut errors := []string{}

	v_exe := vxt.vexe()
	assert v_exe != ''
	vab_home := vabxt.home()
	assert vab_home != ''
	vab_exe := vabxt.vabexe()
	assert vab_exe != ''

	{
		res := run([v_exe, 'test', vab_home])
		if res.exit_code != 0 {
			eprintln(res.output)
			errors << res.output
		}
	}
	{
		res := run([v_exe, 'check-md', '-hide-warnings', vab_home])
		if res.exit_code != 0 {
			eprintln(res.output)
			errors << res.output
		}
	}
	{
		res := run([vab_exe, 'test-cleancode', vab_home])
		if res.exit_code != 0 {
			eprintln(res.output)
			errors << res.output
		}
	}
	{
		res := run([vab_exe, 'test-runtime'])
		if res.exit_code != 0 {
			eprintln(res.output)
			errors << res.output
		}
	}
	if errors.len > 0 {
		eprintln('ERROR: some test(s) failed.')
		exit(1)
	}
}
