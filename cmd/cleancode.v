// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module main

import os
import vab.vxt

const exe_name = os.file_name(os.executable())
const exe_dir = os.dir(os.real_path(os.executable()))

pub fn run(args []string) os.Result {
	cmd := args.join(' ')
	eprintln('${exe_name} running: ${cmd}')
	return os.execute(cmd)
}

fn main() {
	args := os.args[1..]
	mut test_paths := []string{}
	if args.len > 1 {
		test_paths << args[1..]
	}
	if test_paths.len == 0 {
		test_paths << os.getwd()
	}
	v_test_clean_code(test_paths)
}

fn v_test_clean_code(paths []string) {
	mut vet_errors := []string{}
	mut vfmt_errors := []string{}
	for path in paths {
		vet_res := run([vxt.vexe(), 'vet', '-hide-warnings', path])
		if vet_res.exit_code > 0 {
			vet_errors << vet_res.output
		}
		vfmt_res := run([vxt.vexe(), 'fmt', '-verify', path])
		if vfmt_res.exit_code > 0 {
			vfmt_errors << vfmt_res.output
		}
	}

	if vet_errors.len > 0 || vfmt_errors.len > 0 {
		if vet_errors.len > 0 {
			eprintln('WARNING: `v vet` failed.')
			for e in vet_errors {
				eprintln(e)
			}
		}
		if vfmt_errors.len > 0 {
			eprintln('WARNING: `v fmt -verify` failed.')
			for e in vfmt_errors {
				eprintln(e)
			}
		}
		exit(1)
	}
}
