// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module vxt

import os
import regex

// vexe returns the path to the `v` compiler if found
// on the host platform, otherwise a blank `string`.
pub fn vexe() string {
	mut exe := os.getenv('VEXE')
	$if !windows {
		if os.is_executable(exe) {
			return os.real_path(exe)
		}
		possible_symlink := os.find_abs_path_of_executable('v') or { '' }
		if os.is_executable(possible_symlink) {
			return os.real_path(possible_symlink)
		}
	} $else {
		if os.exists(exe) {
			return exe
		}
		system_path := os.find_abs_path_of_executable('v') or { '' }
		if os.exists(system_path) {
			exe = system_path
		}
		if !os.exists(exe) {
			res := os.execute('where.exe v')
			if res.exit_code != 0 {
				exe = ''
			} else {
				return res.output.trim('\n\r')
			}
		}
	}
	// Try the compiler that built this
	if !os.exists(exe) {
		if os.exists(@VEXE) {
			return @VEXE
		}
	}
	return exe
}

// vmodules returns the path to the `.vmodules` folder if found
pub fn vmodules() !string {
	mut vmodules_path := os.getenv('VMODULES')
	if !os.is_dir(vmodules_path) {
		vmodules_path = os.join_path(os.home_dir(), '.vmodules')
	}
	if !os.is_dir(vmodules_path) {
		return error(@MOD + '.' + @FN + ': no valid v modules path found at "${vmodules_path}"')
	}
	return vmodules_path
}

pub fn found() bool {
	return home() != ''
}

pub fn home() string {
	// credits to @spytheman:
	// https://discord.com/channels/592103645835821068/592294828432424960/746040606358503484
	mut exe := vexe()
	$if !windows {
		if os.is_executable(exe) {
			return os.dir(exe)
		}
	} $else {
		if os.exists(exe) {
			exe = exe.replace('/', os.path_separator)
			// Skip the `.bin\` dir
			if os.dir(exe).ends_with('.bin') {
				exe = os.dir(exe)
			}
			return os.dir(exe)
		}
	}
	return ''
}

pub fn version() string {
	mut version := ''
	v := vexe()
	if v != '' {
		v_version := os.execute(v + ' -version')
		if v_version.exit_code != 0 {
			return version
		}
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
		v_version := os.execute(v + ' -version')
		if v_version.exit_code != 0 {
			return ''
		}
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

// v_mod_path returns the path to the `v.mod` file next to `v_file_or_dir_path` if found, an empty string otherwise.
pub fn v_mod_path(v_file_or_dir_path string) string {
	if os.is_dir(v_file_or_dir_path) {
		if os.is_file(os.join_path(v_file_or_dir_path, 'v.mod')) {
			return os.join_path(v_file_or_dir_path, 'v.mod')
		}
	} else {
		if os.is_file(os.join_path(os.dir(v_file_or_dir_path), 'v.mod')) {
			return os.join_path(os.dir(v_file_or_dir_path), 'v.mod')
		}
	}
	return ''
}
