// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module vabxt

import os
import regex

// vabexe returns the path to the `vab` executable if found
// on the host platform, otherwise a blank `string`.
pub fn vabexe() string {
	mut exe := os.getenv('VAB_EXE')
	$if !windows {
		if os.is_executable(exe) {
			return os.real_path(exe)
		}
		possible_symlink := os.find_abs_path_of_executable('vab') or { '' }
		if os.is_executable(possible_symlink) {
			return os.real_path(possible_symlink)
		}
		vmodules_path := vmodules() or { '' }
		if os.is_file(os.join_path(vmodules_path, 'vab', 'vab')) {
			return os.join_path(vmodules_path, 'vab', 'vab')
		}
	} $else {
		if os.exists(exe) {
			return exe
		}
		system_path := os.find_abs_path_of_executable('vab') or { '' }
		if os.exists(system_path) {
			exe = system_path
		}
		if !os.exists(exe) {
			res := os.execute('where.exe vab')
			if res.exit_code != 0 {
				exe = ''
			} else {
				return res.output.trim('\n\r')
			}
		}
		vmodules_path := vmodules() or { '' }
		if os.is_file(os.join_path(vmodules_path, 'vab', 'vab.exe')) {
			return os.join_path(vmodules_path, 'vab', 'vab.exe')
		}
	}

	return exe
}

// vmodules returns the path to the `.vmodules` folder if found.
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

// found returns `true` if `vab` can found on the system, `false` otherwise.
pub fn found() bool {
	return home() != ''
}

// home returns `vab`'s "home" folder. This is usually the directory containing the `vab` executable.
pub fn home() string {
	// credits to @spytheman:
	// https://discord.com/channels/592103645835821068/592294828432424960/746040606358503484
	mut exe := vabexe()
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

// version returns the version of `vab` installed. If `vab` is not installed
// version returns '0.0.0'.
pub fn version() string {
	mut version := ''
	vab := vabexe()
	if vab != '' {
		vab_version := os.execute(vab + ' --version')
		if vab_version.exit_code != 0 {
			return version
		}
		output := vab_version.output
		mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
		start, _ := re.match_string(output)
		if start >= 0 && re.groups.len > 0 {
			version = output[re.groups[0]..re.groups[1]]
		}
		return version
	}
	return '0.0.0'
}

// version_commit_hash returns the VCS commit hash of the `vab` installed.
// If `vab` is not installed or found `deadbeef` is returned.
pub fn version_commit_hash() string {
	mut hash := ''
	vab := vabexe()
	if vab != '' {
		vab_version := os.execute(vab + ' --version')
		if vab_version.exit_code != 0 {
			return ''
		}
		output := vab_version.output
		mut re := regex.regex_opt(r'.*\d+\.?\d*\.?\d* ([a-fA-F0-9]{7,})') or { panic(err) }
		start, _ := re.match_string(output)
		if start >= 0 && re.groups.len > 0 {
			hash = output[re.groups[0]..re.groups[1]]
		}
		return hash
	}
	return 'deadbeef'
}
