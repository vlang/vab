// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module vxt

import os
import regex

pub fn vexe() string {
	mut exe := os.getenv('VEXE')
	if exe != '' {
		return os.real_path(exe)
	}
	possible_symlink := os.find_abs_path_of_executable('v') or { '' }
	if possible_symlink != '' {
		exe = os.real_path(possible_symlink)
	}
	return exe
}

pub fn found() bool {
	return home() != ''
}

pub fn home() string {
	// credits to @spytheman:
	// https://discord.com/channels/592103645835821068/592294828432424960/746040606358503484
	exe := vexe()
	if exe != '' {
		return os.dir(exe)
	}
	return ''
}

pub fn version() string {
	mut version := ''
	v := vexe()
	if v != '' {
		v_version := os.exec(v + ' -version') or { os.Result{1, ''} }
		output := v_version.output
		mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
		start, _ := re.match_string(output)
		if start >= 0 && re.groups.len > 0 {
			version = output[re.groups[0]..re.groups[1]]
		}
		return version
	}
	return '0.0.0'
}

pub fn version_commit_hash() string {
	mut hash := ''
	v := vexe()
	if v != '' {
		v_version := os.exec(v + ' -version') or { os.Result{1, ''} }
		output := v_version.output
		mut re := regex.regex_opt(r'.*\d+\.?\d*\.?\d* ([a-fA-F0-9]{7,})') or { panic(err) }
		start, _ := re.match_string(output)
		if start >= 0 && re.groups.len > 0 {
			hash = output[re.groups[0]..re.groups[1]]
		}
		return hash
	}
	return 'deadbeef'
}
