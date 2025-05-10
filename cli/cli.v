module cli

import os
import flag
import vab.vxt
import vab.vabxt
import vab.java
import vab.paths
import vab.extra
import vab.android
import vab.android.sdk
import vab.android.ndk

pub const exe_version = version()
pub const exe_name = os.file_name(os.executable())
pub const exe_short_name = os.file_name(os.executable()).replace('.exe', '')
pub const exe_dir = os.dir(os.real_path(os.executable()))
pub const exe_args_description = 'input
or:    vab <sub-command> [options] input'

pub const exe_description = 'V Android Bootstrapper.
Compile, package and deploy graphical V apps for Android.

The following flags does the same as if they were passed to the "v" compiler:

-autofree, -gc <type>, -g, -cg, -prod, -showcc,
-skip-unused, -no-bounds-checking

Sub-commands:
  doctor                    Display useful info about your system,
                            (useful for bug reports)
  install                   Install various components. Example:
                            `vab install "platforms;android-21"
  remove                    Remove various components. Example:
                            `vab remove extra github:larpon/vab-sdl'

pub const exe_git_hash = vab_commit_hash()
pub const work_directory = paths.tmp_work()
pub const cache_directory = paths.cache()
pub const rip_vflags = ['-autofree', '-gc', '-g', '-cg', '-prod', 'run', '-showcc', '-skip-unused',
	'-no-bounds-checking'] // NOTE this can be removed when the deprecated `cli.args_to_options()` is removed
pub const subcmds = ['complete', 'test-all', 'test-cleancode', 'test-runtime']
pub const subcmds_builtin = ['doctor', 'install', 'remove']
pub const accepted_input_files = ['.v', '.apk', '.aab']

pub const vab_env_vars = [
	'VAB_FLAGS',
	'VAB_KILL_ADB',
	'ANDROID_SERIAL',
	'ANDROID_HOME',
	'ANDROID_SDK_ROOT',
	'ANDROID_NDK_ROOT',
	'SDKMANAGER',
	'ADB',
	'AVDMANAGER',
	'EMULATOR',
	'BUNDLETOOL',
	'AAPT2',
	'JAVA_HOME',
	'VEXE',
	'VAB_EXE',
	'VMODULES',
]

pub const vab_documentation_config = flag.DocConfig{
	version:     '${exe_short_name} ${version_full()}'
	description: exe_description
	options:     flag.DocOptions{
		compact: true
	}
	fields:      {
		'--gles-version':   'GLES version to use from any of ${android.supported_gles_versions}'
		'--package-format': 'App package format. Any of ${android.supported_package_formats}'
		'--archs':          'Comma separated string with any of:\n${android.default_archs}'
	}
}

// run_vab_sub_command runs a sub-command if found in `args`.
// If the command is found this function will call `exit()` with the
// exit code returned by the executed command.
pub fn run_vab_sub_command(args []string) {
	// Execute extra installed commands first if any match is found
	extra.run_command(args)
	// Run builtin sub-commands, if found
	for subcmd in subcmds {
		if subcmd in args {
			// First encountered known sub-command is executed on the spot
			exit(launch_cmd(args[args.index(subcmd)..]))
		}
	}
}

// input_from_args returns the input argument for `vab` if any, and removes it from `arguments`.
// This function handles `vab`'s' support for arbitrary input placement:
// Examples: `vab /input -o /output`, `vab -o /output /input` and `vab --flag "-d xyz" /input -o /output`.
pub fn input_from_args(arguments []string) (string, []string) {
	mut args := arguments.clone()
	opts, unmatched := options_from_arguments(args, Options{}) or { Options{}, args }
	mut input := opts.input
	if unmatched.len > 0 && (os.is_dir(unmatched[0]) || os.is_file(unmatched[0])) {
		if unmatched[0] != args[0] or { '' } {
			input = unmatched[0]
			args.delete(args.index(input))
		}
	} else if opts.input != '' {
		args.delete(args.index(opts.input))
	}
	return input, args
}

// args_to_options returns an `Option` merged from (CLI/Shell) `arguments` using `defaults` as
// values where no value can be obtained from `arguments`.
@[deprecated: 'use options_from_arguments and run_vab_sub_command instead']
pub fn args_to_options(arguments []string, defaults Options) !(Options, &flag.FlagParser) {
	mut args := arguments.clone()

	// Indentify sub-commands.
	for subcmd in subcmds {
		if subcmd in args {
			// First encountered known sub-command is executed on the spot.
			exit(launch_cmd(args[args.index(subcmd)..]))
		}
	}

	mut v_flags := []string{}
	mut cmd_flags := []string{}
	// Indentify special flags in args before FlagParser ruin them.
	// E.g. the -autofree flag will result in dump_usage being called for some weird reason???
	for special_flag in rip_vflags {
		if special_flag in args {
			if special_flag == '-gc' {
				gc_type := args[(args.index(special_flag)) + 1]
				if gc_type.starts_with('-') {
					return error('flag `-gc` requires an non-flag argument')
				}
				v_flags << special_flag + ' ${gc_type}'
				args.delete(args.index(special_flag) + 1)
			} else if special_flag.starts_with('-') {
				v_flags << special_flag
			} else {
				cmd_flags << special_flag
			}
			args.delete(args.index(special_flag))
		}
	}

	mut fp := flag.new_flag_parser(args)
	fp.application(exe_short_name)
	fp.version(version_full())
	fp.description(exe_description)
	fp.arguments_description(exe_args_description)

	fp.skip_executable()

	mut verbosity := fp.int_opt('verbosity', `v`, 'Verbosity level 1-3') or { defaults.verbosity }
	// TODO implement FlagParser 'is_sat(name string) bool' or something in vlib for this usecase?
	if ('-v' in args || 'verbosity' in args) && verbosity == 0 {
		verbosity = 1
	}

	mut opt := Options{
		assets_extra: fp.string_multi('assets', `a`, 'Asset dir(s) to include in build')
		libs_extra:   fp.string_multi('libs', `l`, 'Lib dir(s) to include in build')
		v_flags:      fp.string_multi('flag', `f`, 'Additional flags for the V compiler')
		//
		c_flags:      fp.string_multi('cflag', `c`, 'Additional flags for the C compiler')
		archs:        fp.string('archs', 0, defaults.archs.join(','), 'Comma separated string with any of ${android.default_archs}').split(',')
		gles_version: fp.int('gles', 0, defaults.gles_version, 'GLES version to use from any of ${android.supported_gles_versions}')
		//
		device_id:        fp.string('device', `d`, defaults.device_id, 'Deploy to device <id>. Use "auto" to use first available.')
		run:              'run' in cmd_flags // fp.bool('run', `r`, false, 'Run the app on the device after successful deployment.')
		device_log:       fp.bool('log', 0, defaults.device_log, 'Enable device logging after deployment.')
		device_log_raw:   fp.bool('log-raw', 0, defaults.device_log_raw, 'Enable unfiltered, full device logging after deployment.')
		clear_device_log: fp.bool('log-clear', 0, defaults.clear_device_log, 'Clear the log buffer on the device before deployment.')
		log_tags:         fp.string_multi('log-tag', 0, 'Additional tags to include in output when using --log')
		//
		keystore:       fp.string('keystore', 0, defaults.keystore, 'Use this keystore file to sign the package')
		keystore_alias: fp.string('keystore-alias', 0, defaults.keystore_alias, 'Use this keystore alias from the keystore file to sign the package')
		//
		dump_usage: fp.bool('help', `h`, defaults.dump_usage, 'Show this help message and exit')
		cache:      !fp.bool('nocache', 0, defaults.cache, 'Do not use build cache')
		//
		app_name:               fp.string('name', 0, defaults.app_name, 'Pretty app name')
		package_id:             fp.string('package-id', 0, defaults.package_id, 'App package ID (e.g. "org.company.app")')
		package_overrides_path: fp.string('package-overrides', 0, defaults.package_overrides_path,
			'Package file overrides path (e.g. "/tmp/java")')
		package_format:         fp.string('package', `p`, defaults.package_format, 'App package format. Any of ${android.supported_package_formats}')
		activity_name:          fp.string('activity-name', 0, defaults.activity_name,
			'The name of the main activity (e.g. "VActivity")')
		icon:                   fp.string('icon', 0, defaults.icon, 'App icon')
		icon_mipmaps:           fp.bool('icon-mipmaps', 0, defaults.icon_mipmaps, 'Generate App mipmap(-xxxhdpi etc.) icons from either `--icon` or, if exists, a .png in app skeleton "res/mipmap" directory')
		version_code:           fp.int('version-code', 0, defaults.version_code, 'Build version code (android:versionCode)')
		//
		output: fp.string('output', `o`, defaults.output, 'Path to output (dir/file)')
		//
		verbosity: verbosity
		parallel:  !fp.bool('no-parallel', 0, false, 'Do not run tasks in parallel.')
		//
		build_tools:     fp.string('build-tools', 0, defaults.build_tools, 'Version of build-tools to use (--list-build-tools)')
		api_level:       fp.string('api', 0, defaults.api_level, 'Android API level to use (--list-apis)')
		min_sdk_version: fp.int('min-sdk-version', 0, defaults.min_sdk_version, 'Minimum SDK version version code (android:minSdkVersion)')
		//
		ndk_version: fp.string('ndk-version', 0, defaults.ndk_version, 'Android NDK version to use (--list-ndks)')
		//
		work_dir: defaults.work_dir
		//
		list_ndks:        fp.bool('list-ndks', 0, defaults.list_ndks, 'List available NDK versions')
		list_apis:        fp.bool('list-apis', 0, defaults.list_apis, 'List available API levels')
		list_build_tools: fp.bool('list-build-tools', 0, defaults.list_build_tools, 'List available Build-tools versions')
		list_devices:     fp.bool('list-devices', 0, defaults.list_devices, 'List available device IDs (including running emulators)')
		//
		screenshot:                fp.string('screenshot', 0, '', 'Take a screenshot on a device and save it to /path/to/file.png or /path/to/directory')
		screenshot_delay:          fp.float('screenshot-delay', 0, 0.0, 'Wait for this amount of seconds before taking screenshot')
		screenshot_on_log:         fp.string('screenshot-on-log', 0, '', 'Wait for this string to appear in the device log before taking a screenshot')
		screenshot_on_log_timeout: fp.float('screenshot-on-log-timeout', 0, 0.0, 'Timeout after this amount of seconds if --screenshot-on-log string is not detected')
	}

	opt.additional_args = fp.finalize() or {
		return error(@FN + ': flag parser failed finalizing: ${err.msg()}')
	}

	mut c_flags := []string{}
	c_flags << opt.c_flags
	for c_flag in defaults.c_flags {
		if c_flag !in c_flags {
			c_flags << c_flag
		}
	}
	opt.c_flags = c_flags

	v_flags << opt.v_flags
	for v_flag in defaults.v_flags {
		if v_flag !in v_flags {
			v_flags << v_flag
		}
	}
	opt.v_flags = v_flags

	mut log_tags := []string{}
	log_tags << opt.log_tags
	for log_tag in defaults.log_tags {
		if log_tag !in log_tags {
			log_tags << log_tag
		}
	}
	opt.log_tags = log_tags

	return opt, fp
}

// check_essentials ensures that the work environment has all needed dependencies
// and meet all required needs.
pub fn check_essentials(exit_on_error bool) {
	// Validate V install
	if vxt.vexe() == '' {
		eprintln('No V install could be detected')
		eprintln('Please install V from https://github.com/vlang/v')
		eprintln('or provide a valid path to V via VEXE env variable')
		if exit_on_error {
			exit(1)
		}
	}
	// Validate Java requirements
	if !java.jdk_found() {
		eprintln('No Java install(s) could be detected')
		eprintln('Please install Java JDK >= 8 or provide a valid path via JAVA_HOME')
		if exit_on_error {
			exit(1)
		}
	}

	// Validate keytool
	keytool := java.jdk_keytool() or {
		eprintln('Warning: could not locate `keytool`: ${err}')
		''
	}
	if keytool == '' {
		eprintln('${exe_short_name} will not be able to sign any packages.')
		if javac := java.jdk_javac() {
			eprintln('It looks like you have a Java compiler (${javac}) but no `keytool`')
			eprintln('you probably have Java JRE installed but no JDK.')
		}
		eprintln('Please install Java JDK >= 8 or provide a valid path via JAVA_HOME')
		if exit_on_error {
			exit(1)
		}
	}

	// Validate Android SDK requirements
	if !sdk.found() {
		eprintln('No Android SDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `${exe_short_name} install auto`')
		if exit_on_error {
			exit(1)
		}
	}
	// Validate Android NDK requirements
	if !ndk.found() {
		eprintln('No Android NDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
		eprintln('or run `${exe_short_name} install ndk`')
		if exit_on_error {
			exit(1)
		}
	}
}

// dot_vab_path returns the path to the `.vab` file next to `file_or_dir_path` if found, an empty string otherwise.
pub fn dot_vab_path(file_or_dir_path string) string {
	if os.is_dir(file_or_dir_path) {
		if os.is_file(os.join_path(file_or_dir_path, '.vab')) {
			return os.join_path(file_or_dir_path, '.vab')
		}
	} else {
		if os.is_file(os.join_path(os.dir(file_or_dir_path), '.vab')) {
			return os.join_path(os.dir(file_or_dir_path), '.vab')
		}
	}
	return ''
}

// launch_cmd launches an external command.
pub fn launch_cmd(args []string) int {
	mut cmd := args[0]
	tool_args := args[1..]
	if cmd.starts_with('test-') {
		cmd = cmd.all_after('test-')
	}
	v := vxt.vexe()
	tool_exe := os.join_path(exe_dir, 'cmd', cmd)
	if os.is_executable(v) {
		hash_file := os.join_path(exe_dir, 'cmd', '.' + cmd + '.hash')

		mut hash := ''
		if os.is_file(hash_file) {
			hash = os.read_file(hash_file) or { '' }
		}
		if hash != exe_git_hash {
			v_cmd := [
				v,
				tool_exe + '.v',
				'-o',
				tool_exe,
			]
			res := os.execute(v_cmd.join(' '))
			if res.exit_code < 0 {
				panic(@MOD + '.' + @FN + ' failed compiling "${cmd}": ${res.output}')
			}
			if res.exit_code == 0 {
				os.write_file(hash_file, exe_git_hash) or {}
			} else {
				vcmd := v_cmd.join(' ')
				eprintln(@MOD + '.' + @FN + ' "${vcmd}" failed.')
				eprintln(res.output)
				return 1
			}
		}
	}
	if os.is_executable(tool_exe) {
		if vabxt.found() {
			os.setenv('VAB_EXE', vabxt.vabexe(), true)
		}
		$if windows {
			exit(os.system('${os.quoted_path(tool_exe)} ${tool_args}'))
		} $else $if js {
			// no way to implement os.execvp in JS backend
			exit(os.system('${tool_exe} ${tool_args}'))
		} $else {
			os.execvp(tool_exe, args) or { panic(err) }
		}
		exit(2)
	}
	exec := (tool_exe + ' ' + tool_args.join(' ')).trim_right(' ')
	v_message := if !os.is_executable(v) { ' (v was not found)' } else { '' }
	eprintln(@MOD + '.' + @FN + ' failed executing "${exec}"${v_message}')
	return 1
}

// string_to_args converts `input` string to an `os.args`-like array.
// string_to_args preserves strings delimited by both `"` and `'`.
pub fn string_to_args(input string) ![]string {
	mut args := []string{}
	mut buf := ''
	mut in_string := false
	mut delim := u8(` `)
	for ch in input {
		if ch in [`"`, `'`] {
			if !in_string {
				delim = ch
			}
			in_string = !in_string && ch == delim
			if !in_string {
				if buf != '' && buf != ' ' {
					args << buf
				}
				buf = ''
				delim = ` `
			}
			continue
		}
		buf += ch.ascii_str()
		if !in_string && ch == ` ` {
			if buf != '' && buf != ' ' {
				args << buf[..buf.len - 1]
			}
			buf = ''
			continue
		}
	}
	if buf != '' && buf != ' ' {
		args << buf
	}
	if in_string {
		return error(@FN +
			': could not parse input, missing closing string delimiter `${delim.ascii_str()}`')
	}
	return args
}

// validate_input validates `input` for use with vab.
pub fn validate_input(input string) ! {
	input_ext := os.file_ext(input)

	accepted_input_ext := input_ext in accepted_input_files
	if !(os.is_dir(input) || accepted_input_ext) {
		return error('input should be a V file, an APK, AAB or a directory containing V sources')
	}
	if accepted_input_ext {
		if !os.is_file(input) {
			return error('input should be a V file, an APK, AAB or a directory containing V sources')
		}
	}
}
