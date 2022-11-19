module cli

import os

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

fn vab_tmp_work_dir() string {
	return os.join_path(os.temp_dir(), exe_name.replace(' ', '_').replace('.exe', '').to_lower())
}

fn vab_cache_dir() string {
	return os.join_path(os.cache_dir(), exe_name.replace(' ', '_').replace('.exe', '').to_lower())
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
