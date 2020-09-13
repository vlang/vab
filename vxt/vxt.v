module vxt

import os
import regex

pub fn vexe() string {
	env_vexe := os.getenv('VEXE')
    if env_vexe != '' {
        return env_vexe
    }
    possible_symlink := os.find_abs_path_of_executable('v') or { panic('can not find v') }
    vexe := os.real_path( possible_symlink )
    return vexe
}

pub fn home() string {
	// credits to @spytheman:
	// https://discord.com/channels/592103645835821068/592294828432424960/746040606358503484
	/*env_vexe := os.getenv('VEXE')
    if env_vexe != '' {
        return os.dir(env_vexe)
    }
    possible_symlink := os.find_abs_path_of_executable('v') or { panic('can not find v') }
    vexe := os.real_path( possible_symlink )*/
    return os.dir(vexe())
}

pub fn version() string {
	mut version := ''
	v := vexe()
	v_version := os.exec(v+' -version') or { os.Result{1,''} }
	output := v_version.output
	mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
	start, _ := re.match_string(output)
	if start >= 0 && re.groups.len > 0 {
		version = output[re.groups[0]..re.groups[1]]
	}
	return version
}
