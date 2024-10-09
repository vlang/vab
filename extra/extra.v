// Copyright(C) 2019-2024 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
// This module handles everything related to extra commands.
module extra

import os
import strings
import compress.szip
import vab.paths
import vab.util
import vab.vxt
import net.http

const valid_sources = ['github']
pub const command_prefix = 'vab'
pub const data_path = os.join_path(paths.data(), 'extra')
pub const temp_path = os.join_path(paths.tmp_work(), 'extra')

@[params]
pub struct InstallOptions {
pub:
	input     []string
	verbosity int
}

pub struct Command {
pub:
	id     string
	alias  string
	source string
	unit   string
	hash   string
	exe    string
}

struct GitHubInfo {
pub:
	sha string
	url string
}

// verbose prints `msg` to STDOUT if `InstallOptions.verbosity` level is >= `verbosity_level`.
pub fn (io &InstallOptions) verbose(verbosity_level int, msg string) {
	if io.verbosity >= verbosity_level {
		println(msg)
	}
}

// run_command runs a extra installed command if found in `args`.
// If the command is found this function will call `exit()` with the result
// returned by the executed command.
pub fn run_command(args []string) {
	// Indentify extra installed commands
	extra_commands := commands()
	for _, extra_command in extra_commands {
		short_id := extra_command.id.trim_left('${command_prefix}-')
		if short_id in args {
			mut complete_index := args.len
			if 'complete' in args {
				complete_index = args.index('complete')
			}
			short_id_index := args.index(short_id)
			if complete_index < short_id_index {
				// if `complete` is found before the extra command vab is
				// highly likely trying to tab complete something in which case
				// nothing nothing should be executed
				return
			}
			// First encountered known sub-command is executed on the spot.
			exit(launch_command(args[short_id_index..]))
		}
	}
}

fn launch_command(args []string) int {
	$if !vab_allow_extra_commands ? {
		util.vab_error('To enable running extra commands, pass `-d vab_allow_extra_commands` when building vab')
		exit(2)
	}
	mut cmd := args[0]
	extra_commands := commands()
	if command := extra_commands['${command_prefix}-' + cmd] {
		tool_args := args[1..].clone()
		tool_exe := command.exe
		if os.is_executable(tool_exe) {
			// os.setenv('VAB_EXE', os.join_path(exe_dir, exe_name), true)
			$if windows {
				exit(os.system('${os.quoted_path(tool_exe)} ${tool_args}'))
			} $else $if js {
				// no way to implement os.execvp in JS backend
				exit(os.system('${tool_exe} ${tool_args}'))
			} $else {
				os.execvp(tool_exe, tool_args) or { panic(err) }
			}
			exit(2)
		}
		exec := (tool_exe + ' ' + tool_args.join(' ')).trim_right(' ')
		eprintln(@MOD + '.' + @FN + ' failed executing "${exec}"')
		return 1
	}

	eprintln(@MOD + '.' + @FN + ' failed to identify "${args}"')
	return 1
}

// install_command retrieves, installs and registers external extra commands
pub fn install_command(opt InstallOptions) ! {
	// `vab install cmd xyz/abc`
	if opt.input.len == 0 {
		return error('${@FN} requires input')
	}

	component := opt.input[0] // Only 1 argument needed for now
	if component.count(':') == 0 {
		// no source protocol detected, slap on default and try again...
		mod_opt := InstallOptions{
			...opt
			input: ['github:${component}']
		}
		return install_command(mod_opt)
	}

	$if !vab_allow_extra_commands ? {
		util.vab_notice('To enable running extra commands, pass `-d vab_allow_extra_commands` when building vab')
	}

	source := component.all_before(':')
	if source !in valid_sources {
		return error('${@FN} unknown source `${source}`. Valid sources are ${valid_sources}')
	}
	unit := component.all_after(':')

	match source {
		'github' {
			return install_from_github(unit, opt.verbosity)
		}
		else {
			return error('${@FN} unknown source `${source}`. Valid sources are ${valid_sources}')
		}
	}
}

fn install_from_github(unit string, verbosity int) ! {
	if unit.count('/') != 1 {
		return error('${@MOD} ${@FN} `${unit}` should contain exactly one "/" character')
	}
	unit_parts := unit.split('/')

	// TODO: support @ notation for specific commits/branches?
	// mut at_part := unit.all_after('@')

	if !(valid_identifier(unit_parts[0]) && valid_identifier(unit_parts[1])) {
		return error('${@MOD} ${@FN} `${unit}` is not a valid identifier')
	}

	cmd_author := unit_parts[0]
	cmd_name := unit_parts[1]
	if has_command(cmd_name) {
		extra_commands := commands()
		if command := extra_commands[cmd_name] {
			if command.unit != unit {
				return error('${@MOD} ${@FN} `${unit}` is already installed from `${command.unit}` via ${command.source}')
			}
		}
	}

	initial_dst := os.join_path(data_path, 'commands', 'github', cmd_author)

	tmp_downloads := os.join_path(temp_path, 'downloads')
	paths.ensure(tmp_downloads)!

	github_info := get_github_info(unit)!

	sha := github_info.sha
	url := github_info.url

	zip_file := os.join_path(tmp_downloads, 'github-${unit.replace('/', '-')}.${sha}.zip')
	if !os.exists(zip_file) {
		if verbosity > 1 {
			println('Downloading `${unit}` from "${url}"...')
		}
		http.download_file(url, zip_file) or {
			return error('${@MOD} ${@FN} failed to download `${unit}`: ${err}')
		}
	}
	final_dst := os.join_path(initial_dst, unit_parts[1])
	// Install
	if verbosity > 1 {
		println('Installing `${unit}` to "${final_dst}"...')
	}
	paths.ensure(initial_dst)!

	unzip(zip_file, initial_dst)!
	unzipped_dst := os.join_path(initial_dst, '${cmd_name}-${sha}')
	if os.exists(final_dst) {
		os.rmdir_all(final_dst) or {}
	}
	os.mv(unzipped_dst, final_dst)!

	build_command(final_dst, verbosity)!
	record_install(cmd_name, 'github', unit, sha)!
}

fn record_install(id string, source string, unit string, hash string) ! {
	path := data_path
	paths.ensure(path)!
	installs_db := os.join_path(path, 'installed.txt')
	installs_db_bak := os.join_path(path, 'installed.txt.bak')
	if !os.exists(installs_db) {
		os.create(installs_db)!
	}
	mut installs := os.read_lines(installs_db)!

	for i, install_line in installs {
		if install_line == '' || install_line.starts_with('#') {
			continue
		}
		split := install_line.split(';')
		if split.len > 2 {
			if split[1] == source && split[2] == unit {
				installs.delete(i)
				break
			}
		}
	}
	installs << '${id};${source};${unit};${hash}'
	os.mv(installs_db, installs_db_bak, overwrite: true)!
	os.write_lines(installs_db, installs)!
}

fn get_github_info(unit string) !GitHubInfo {
	tmp_downloads := os.join_path(temp_path, 'downloads')
	paths.ensure(tmp_downloads)!

	base_url := 'https://api.github.com/repos/${unit}'
	meta_file := os.join_path(tmp_downloads, 'github-${unit.replace('/', '-')}.meta')
	http.download_file(base_url, meta_file) or {
		return error('${@MOD} ${@FN} failed to download `${base_url}`: ${err}')
	}

	default_branch := os.read_file(meta_file)!.all_after('default_branch').trim_left('" ,:').all_before('"')

	refs_url := '${base_url}/git/refs/heads'
	refs_file := os.join_path(tmp_downloads, 'github-${unit.replace('/', '-')}.refs')
	http.download_file(refs_url, refs_file) or {
		return error('${@MOD} ${@FN} failed to download `${refs_url}`: ${err}')
	}

	mut raw := strings.find_between_pair_u8(os.read_file(refs_file)!, `[`, `]`)
	mut found := false
	mut chunk := ''
	ref := 'refs/heads/${default_branch}'
	for _ in 0 .. 20 {
		chunk = strings.find_between_pair_u8(raw, `{`, `}`)
		if chunk.contains(ref) {
			found = true
			break
		}
		raw = raw.replace('{${chunk}}', '')
	}
	if !found {
		return error('${@MOD} ${@FN} failed to get git information via `${refs_url}`')
	}

	sha := chunk.all_after('sha').trim_left('" ,:').all_before('"')
	url := 'https://github.com/${unit}/archive/${sha}.zip'
	return GitHubInfo{
		sha: sha
		url: url
	}
}

// installed returns an array of the extra commands installed via
// `vab install extra ...`
// See also: installed_aliases
pub fn installed() []string {
	cmds := commands()
	return cmds.keys()
}

// installed_aliases returns an array of the extra commands' aliases installed via
// `vab install extra ...`
// See also: installed
pub fn installed_aliases() []string {
	mut aliases := []string{}
	for id, _ in commands() {
		aliases << id.trim_left('${command_prefix}-')
	}
	return aliases
}

// has_command returns `true` if `command` is installed as an extra command
pub fn has_command(command string) bool {
	cmds := commands()
	return command in cmds.keys()
}

// has_command_alias returns `true` if `alias` is installed as an extra command
pub fn has_command_alias(alias string) bool {
	cmds := commands()
	for _, extra_command in cmds {
		if extra_command.id.trim_left('${command_prefix}-') == alias {
			return true
		}
	}
	return false
}

// commands returns all extra commands installed via
// `vab install extra ...`
// See also: installed
pub fn commands() map[string]Command {
	mut installed := map[string]Command{}
	path := data_path
	installs_db := os.join_path(path, 'installed.txt')
	if os.exists(installs_db) {
		installs := os.read_lines(installs_db) or { return installed }
		for install_line in installs {
			if install_line == '' || install_line.starts_with('#') {
				continue
			}
			split := install_line.split(';')
			if split.len > 3 {
				id := split[0]
				alias := id.trim_left('${command_prefix}-')
				source := split[1] or { 'unknown' }
				unit := split[2] or { 'unknown/unknown' }
				hash := split[3] or { 'deadbeef' }
				unit_parts := unit.split('/')
				final_dst := os.join_path(data_path, 'commands', source, unit_parts[0],
					unit_parts[1])

				installed[id] = Command{
					id:     id
					alias:  alias
					source: source
					unit:   unit
					hash:   hash
					exe:    os.join_path(final_dst, id)
				}
			}
		}
	}
	return installed
}

fn unzip(file string, dir string) ! {
	if !os.is_dir(dir) {
		os.mkdir_all(dir)!
	}
	szip.extract_zip_to_dir(file, dir)!
}

fn valid_identifier(s string) bool {
	if s.len == 0 {
		return false
	}
	for ch in s {
		if !(ch.is_letter() || ch.is_digit() || ch == `_` || ch == `-`) {
			return false
		}
	}
	return true
}

fn build_command(path string, verbosity int) ! {
	if !vxt.found() {
		return error('${@MOD} ${@FN} failed to locate a V compiler')
	}
	v_exe := vxt.vexe()
	v_cmd := [
		v_exe,
		path,
	]
	verbosity_print_cmd(v_cmd, verbosity)
	res := run(v_cmd)
	if res.exit_code != 0 {
		return error('${@MOD} ${@FN} "${v_cmd.join(' ')}" failed:\n${res.output}')
	}
}

// verbosity_print_cmd prints information about the `args` at certain `verbosity` levels.
fn verbosity_print_cmd(args []string, verbosity int) {
	if args.len > 0 && verbosity > 1 {
		cmd_short := args[0].all_after_last(os.path_separator)
		mut output := 'Running ${cmd_short} From: ${os.getwd()}'
		if verbosity > 2 {
			output += '\n' + args.join(' ')
		}
		println(output)
	}
}

fn run(args []string) os.Result {
	res := os.execute(args.join(' '))
	return res
}
