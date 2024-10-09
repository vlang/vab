module cli

import os
import strings
import vab.extra

// kill_adb will try to kill the `adb` process.
pub fn kill_adb() {
	uos := os.user_os()
	println('Killing adb ...')
	if uos == 'windows' {
		// os.system('Taskkill /IM adb.exe /F') // TODO Untested
	} else {
		os.system('killall adb')
	}
}

fn vab_commit_hash() string {
	mut hash := ''
	git_exe := os.find_abs_path_of_executable('git') or { '' }
	if git_exe != '' {
		mut git_cmd := 'git -C "${exe_dir}" rev-parse --short HEAD'
		$if windows {
			git_cmd = 'git.exe -C "${exe_dir}" rev-parse --short HEAD'
		}
		res := os.execute(git_cmd)
		if res.exit_code == 0 {
			hash = res.output
		}
	}
	return hash.trim_space()
}

fn version_full() string {
	return '${exe_version} ${exe_git_hash}'
}

fn version() string {
	mut v := '0.0.0'
	vmod := @VMOD_FILE
	if vmod.len > 0 {
		if vmod.contains('version:') {
			v = vmod.all_after('version:').all_before('\n').replace("'", '').replace('"',
				'').trim_space()
		}
	}
	return v
}

// input_suggestions returns alternative suggestions to the `input` string.
pub fn input_suggestions(input string) []string {
	mut suggests := []string{}
	$if vab_allow_extra_commands ? {
		for extra_alias in extra.installed_aliases() {
			similarity := f32(int(strings.levenshtein_distance_percentage(input, extra_alias) * 1000)) / 1000
			if similarity > 0.25 {
				suggests << extra_alias
			}
		}
	}
	return suggests
}
