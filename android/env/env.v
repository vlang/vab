// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module env

import os
import semver
import net.http
import vab.cache
import vab.extra
import vab.util as vabutil
import vab.android.sdk
import vab.android.ndk
import vab.android.util

pub const accepted_components = ['auto', 'cmdline-tools', 'platform-tools', 'ndk', 'platforms',
	'build-tools', 'bundletool', 'aapt2', 'emulator', 'system-images']
// 6858069 = cmdline-tools;3.0 <- zip structure changes *sigh*
// 6609375 = cmdline-tools;2.1 <- latest that support `sdkmanager --version` *sigh*
// cmdline-tools-bootstrap-url - Replace [XXX] with linux/mac/win
// cmdline-tools - Latest more or less sane version that works with java versions >= 8 ...
// sdk - Latest
// ndk - Works with android.compile(...)
// platform - Google Play minimum
// build-tools - Version where apksigner is included from

@[deprecated: 'use get_default_components() instead']
pub const default_components = {
	'cmdline-tools':  {
		'name':          'cmdline-tools'
		'version':       '2.1'
		'bootstrap_url': 'https://dl.google.com/android/repository/commandlinetools-[XXX]-6609375_latest.zip'
	}
	'platform-tools': {
		'name':    'platform-tools'
		'version': ''
	}
	'ndk':            {
		'name':    'ndk'
		'version': ndk.min_supported_version
	}
	'platforms':      {
		'name':    'platforms'
		'version': 'android-' + sdk.min_supported_api_level
	}
	'build-tools':    {
		'name':    'build-tools'
		'version': sdk.min_supported_build_tools_version
	}
	'bundletool':     {
		'name':          'bundletool'
		'version':       '1.5.0'
		'bootstrap_url': 'https://github.com/google/bundletool/releases/download/1.5.0/bundletool-all-1.5.0.jar'
	}
	'aapt2':          {
		'name':          'aapt2'
		'version':       '7.0.0'
		'bootstrap_url': 'https://dl.google.com/android/maven2/com/android/tools/build/aapt2/7.0.0-alpha07-7087017/aapt2-7.0.0-alpha07-7087017-[XXX].jar'
	}
	'emulator':       {
		'name':    'emulator'
		'version': ''
	}
	'system-images':  {
		'name':    'system-images'
		'version': ''
	}
}

pub const default_components_eq_java_8 = {
	'cmdline-tools':  {
		'name':          'cmdline-tools'
		'version':       '2.1'
		'bootstrap_url': 'https://dl.google.com/android/repository/commandlinetools-[XXX]-6609375_latest.zip'
	}
	'platform-tools': {
		'name':    'platform-tools'
		'version': ''
	}
	'ndk':            {
		'name':    'ndk'
		'version': ndk.min_supported_version
	}
	'platforms':      {
		'name':    'platforms'
		'version': 'android-' + sdk.min_supported_api_level
	}
	'build-tools':    {
		'name':    'build-tools'
		'version': sdk.min_supported_build_tools_version
	}
	'bundletool':     {
		'name':          'bundletool'
		'version':       '1.5.0'
		'bootstrap_url': 'https://github.com/google/bundletool/releases/download/1.5.0/bundletool-all-1.5.0.jar'
	}
	'aapt2':          {
		'name':          'aapt2'
		'version':       '7.0.0'
		'bootstrap_url': 'https://dl.google.com/android/maven2/com/android/tools/build/aapt2/7.0.0-alpha07-7087017/aapt2-7.0.0-alpha07-7087017-[XXX].jar'
	}
	'emulator':       {
		'name':    'emulator'
		'version': ''
	}
	'system-images':  {
		'name':    'system-images'
		'version': ''
	}
}

// get_default_components returns the default components map based on what Java version is being used
pub fn get_default_components() !map[string]map[string]string {
	return default_components_eq_java_8
}

pub const dot_exe = $if windows {
	'.exe'
} $else {
	''
}

// Possible locations of the `sdkmanager` tool
// https://stackoverflow.com/a/61176718
const possible_relative_to_sdk_sdkmanager_paths = [
	os.join_path('cmdline-tools', 'latest', 'bin'),
	os.join_path('tools', 'latest', 'bin'),
	os.join_path('cmdline-tools', 'tools', 'bin'),
	os.join_path('tools', 'bin'),
]
const work_path = os.join_path(os.temp_dir(), 'vab', 'tmp')

pub enum Dependency {
	platform_tools
	ndk
	platforms
	build_tools
	cmdline_tools
	bundletool
	aapt2
	emulator
	system_images
}

pub struct InstallOptions {
	dep       Dependency
	item      string
	verbosity int
}

// verbose prints `msg` to STDOUT if `InstallOptions.verbosity` level is >= `verbosity_level`.
pub fn (io &InstallOptions) verbose(verbosity_level int, msg string) {
	if io.verbosity >= verbosity_level {
		println(msg)
	}
}

pub fn managable() bool {
	sdk_is_writable := os.is_writable(sdk.root())
	// sdkmanager checks
	sdkm := sdkmanager()
	has_sdkmanager := sdkm != ''
	mut sdkmanger_works := false
	if has_sdkmanager {
		// We have detected `sdkmanager` - but does it work with the Java version? *sigh*
		// Android development will let us find out I guess:
		cmd := [
			sdkm,
			'--list',
		]
		mut cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			// Failed let's try a workaround from stackoverflow:
			// https://stackoverflow.com/a/51644855/1904615
			if 'windows' == os.user_os() {
				util.run([
					'set JAVA_OPTS=-XX:+IgnoreUnrecognizedVMOptions --add-modules java.se.ee',
				])
				util.run([
					'set JAVA_OPTS=-XX:+IgnoreUnrecognizedVMOptions --add-modules java.xml.bind',
				])
			} else {
				util.run([
					"export JAVA_OPTS='-XX:+IgnoreUnrecognizedVMOptions --add-modules java.se.ee'",
				])
				util.run([
					"export JAVA_OPTS='-XX:+IgnoreUnrecognizedVMOptions --add-modules java.xml.bind'",
				])
			}
			// Let try again
			cmd_res = util.run(cmd)
			if cmd_res.exit_code == 0 {
				sdkmanger_works = true
			}
			// Give up trying to fix this horrible eco-system
		} else {
			sdkmanger_works = true
		}
	}
	return sdk_is_writable && has_sdkmanager && sdkmanger_works
}

@[deprecated: 'use install_components instead']
pub fn install(components string, verbosity int) int {
	mut iopts := []InstallOptions{}
	mut ensure_sdk := true

	// Allows to specify a string list of things to install
	components_array := components.split(',')
	for comp in components_array {
		mut component := comp.trim_space()
		mut version := ''
		is_auto := component.contains('auto')

		def_components := get_default_components() or {
			eprintln(err)
			return 1
		}
		mut split_component := []string{}
		if !is_auto {
			version = def_components[component]['version'] // Set default version
			if component.contains(';') { // If user has specified a version, use that
				split_component = component.split(';')
				component = split_component.first()
				version = split_component.last()
			}
		}

		if component !in accepted_components {
			eprintln(@MOD + ' ' + @FN + ' component "${component}" not recognized.')
			eprintln('Available components ${accepted_components}.')
			return 1
		}

		if !is_auto {
			if version == '' {
				if component !in ['platform-tools', 'emulator', 'system-images'] {
					eprintln(@MOD + ' ' + @FN + ' install component "${component}" has no version.')
					return 1
				}
			}
			if component == 'system-images' {
				if split_component.len != 4 {
					eprintln(@MOD + ' ' + @FN +
						' install component "${component}" should be 4 fields delimited by `;`.')
					return 1
				}
			}
		}

		item := if version != '' { component + ';' + version } else { component }

		match component {
			'auto' {
				cmdline_tools_comp := def_components['cmdline-tools']['name'] + ';' +
					def_components['cmdline-tools']['version']
				platform_tools_comp := def_components['platform-tools']['name'] //+ ';' + def_components['platform-tools']['version']
				ndk_comp := def_components['ndk']['name'] + ';' + def_components['ndk']['version']
				build_tools_comp := def_components['build-tools']['name'] + ';' +
					def_components['build-tools']['version']
				platforms_comp := def_components['platforms']['name'] + ';' +
					def_components['platforms']['version']
				iopts = [
					InstallOptions{.cmdline_tools, cmdline_tools_comp, verbosity},
					InstallOptions{.platform_tools, platform_tools_comp, verbosity},
					InstallOptions{.ndk, ndk_comp, verbosity},
					InstallOptions{.build_tools, build_tools_comp, verbosity},
					InstallOptions{.platforms, platforms_comp, verbosity},
				]
				break
			}
			'cmdline-tools' {
				iopts << InstallOptions{.cmdline_tools, item, verbosity}
			}
			'platform-tools' {
				iopts << InstallOptions{.platform_tools, item, verbosity}
			}
			'emulator' {
				iopts << InstallOptions{.emulator, item, verbosity}
			}
			'system-images' {
				iopts << InstallOptions{.system_images, comp, verbosity}
			}
			'ndk' {
				iopts << InstallOptions{.ndk, item, verbosity}
			}
			'build-tools' {
				iopts << InstallOptions{.build_tools, item, verbosity}
			}
			'platforms' {
				iopts << InstallOptions{.platforms, item, verbosity}
			}
			'bundletool' {
				ensure_sdk = false
				iopts << InstallOptions{.bundletool, item, verbosity}
			}
			'aapt2' {
				ensure_sdk = false
				iopts << InstallOptions{.aapt2, item, verbosity}
			}
			else {
				eprintln(@MOD + ' ' + @FN + ' unknown component "${component}"')
				return 1
			}
		}
	}

	if ensure_sdk {
		ensure_sdkmanager(verbosity) or {
			eprintln(err)
			return 1
		}
	}

	for iopt in iopts {
		install_opt(iopt) or {
			eprintln(err)
			return 1
		}
	}
	return 0
}

// remove_components removess various external components installed by `install_components`
// These components can be (TODO: Android SDK components or) extra commands.
pub fn remove_components(arguments []string, verbosity int) ! {
	if arguments.len == 0 {
		return error('${@FN} requires at least one argument')
	}

	mut args := arguments.clone()
	if args[0] == 'remove' {
		args = args[1..].clone() // skip `remove` part
	}
	if args.len == 0 {
		return error('${@FN} requires an argument')
	}

	components := args[0]
	// vab remove extra ...
	if components == 'extra' {
		if args.len == 1 {
			return error('${@FN} extra requires an argument')
		}
		extra.remove_command(input: args[1..].clone(), verbosity: verbosity) or {
			return error('Removing of command failed: ${err}')
		}
		if verbosity > 0 {
			println('Removed successfully')
		}
		return
	}

	// TODO: vab remove "x;y;z,i;j;k" (sdkmanager compatible tuple)
	// Allows to specify a string list of things to remove
	return error('${@FN} TODO: currently `remove` only supports removing extra commands via `vab remove extra ...`')
	// if verbosity > 0 {
	// 	println('Removed successfully')
	// }
}

// install_components installs various external components that vab can use.
// These components can be Android SDK components or extra commands.
pub fn install_components(arguments []string, verbosity int) ! {
	mut iopts := []InstallOptions{}
	mut ensure_sdk := true

	if arguments.len == 0 {
		return error('${@FN} requires at least one argument')
	}

	mut args := arguments.clone()
	if args[0] == 'install' {
		args = args[1..].clone() // skip `install` part
	}
	if args.len == 0 {
		return error(@FN + ' requires an argument')
	}

	components := args[0]
	// vab install extra ...
	if components == 'extra' {
		if args.len == 1 {
			return error('${@FN} extra requires an argument')
		}
		extra.install_command(input: args[1..].clone(), verbosity: verbosity) or {
			return error('Installing of command failed: ${err}')
		}
		return
	}

	// vab install "x;y;z,i;j;k" (sdkmanager compatible tuple)
	// Allows to specify a string list of things to install
	components_array := components.split(',')
	for comp in components_array {
		mut component := comp.trim_space()
		mut version := ''
		is_auto := component.contains('auto')

		def_components := get_default_components()!
		mut split_component := []string{}
		if !is_auto {
			version = def_components[component]['version'] // Set default version
			if component.contains(';') { // If user has specified a version, use that
				split_component = component.split(';')
				component = split_component.first()
				version = split_component.last()
			}
		}

		if component !in accepted_components {
			return error('${@FN} component "${component}" not recognized. Available components ${accepted_components}.')
		}

		if !is_auto {
			if version == '' {
				if component !in ['platform-tools', 'emulator', 'system-images'] {
					return error('${@FN} install component "${component}" has no version.')
				}
			}
			if component == 'system-images' {
				if split_component.len != 4 {
					return error('${@FN} install component "${component}" should be 4 fields delimited by `;`.')
				}
			}
		}

		item := if version != '' { component + ';' + version } else { component }

		match component {
			'auto' {
				cmdline_tools_comp := def_components['cmdline-tools']['name'] + ';' +
					def_components['cmdline-tools']['version']
				platform_tools_comp := def_components['platform-tools']['name'] //+ ';' + def_components['platform-tools']['version']
				ndk_comp := def_components['ndk']['name'] + ';' + def_components['ndk']['version']
				build_tools_comp := def_components['build-tools']['name'] + ';' +
					def_components['build-tools']['version']
				platforms_comp := def_components['platforms']['name'] + ';' +
					def_components['platforms']['version']
				iopts = [
					InstallOptions{.cmdline_tools, cmdline_tools_comp, verbosity},
					InstallOptions{.platform_tools, platform_tools_comp, verbosity},
					InstallOptions{.ndk, ndk_comp, verbosity},
					InstallOptions{.build_tools, build_tools_comp, verbosity},
					InstallOptions{.platforms, platforms_comp, verbosity},
				]
				break
			}
			'cmdline-tools' {
				iopts << InstallOptions{.cmdline_tools, item, verbosity}
			}
			'platform-tools' {
				iopts << InstallOptions{.platform_tools, item, verbosity}
			}
			'emulator' {
				iopts << InstallOptions{.emulator, item, verbosity}
			}
			'system-images' {
				iopts << InstallOptions{.system_images, comp, verbosity}
			}
			'ndk' {
				iopts << InstallOptions{.ndk, item, verbosity}
			}
			'build-tools' {
				iopts << InstallOptions{.build_tools, item, verbosity}
			}
			'platforms' {
				iopts << InstallOptions{.platforms, item, verbosity}
			}
			'bundletool' {
				ensure_sdk = false
				iopts << InstallOptions{.bundletool, item, verbosity}
			}
			'aapt2' {
				ensure_sdk = false
				iopts << InstallOptions{.aapt2, item, verbosity}
			}
			else {
				return error('${@FN} unknown component "${component}"')
			}
		}
	}

	if ensure_sdk {
		ensure_sdkmanager(verbosity)!
	}

	for iopt in iopts {
		install_opt(iopt)!
	}

	if verbosity > 0 {
		if components != 'auto' {
			println('Installed ${components} successfully')
		} else {
			println('Installed all dependencies successfully')
		}
	}
}

fn install_opt(opt InstallOptions) !bool {
	loose := opt.dep == .bundletool || opt.dep == .aapt2

	if !loose && !managable() {
		if !os.is_writable(sdk.root()) {
			return error(@MOD + '.' + @FN + ' ' +
				'No permission to write in Android SDK root. Please install manually or ensure write access to "${sdk.root()}".')
		} else {
			return error(@MOD + '.' + @FN + ' ' +
				'The `sdkmanager` seems outdated or incompatible with the Java version used". Please fix your setup manually.\nPath: "${sdkmanager()}"\nVersion: ${sdkmanager_version()}')
		}
	}

	// Accept all SDK licenses
	$if windows {
		os.mkdir_all(work_path) or {}
		yes_file := os.join_path(work_path, 'yes.txt')
		os.write_file(yes_file, 'y\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny\r\ny')!

		cmd := [
			'cmd /c',
			'""' + sdkmanager() + '"',
			'--sdk_root="${sdk.root()}"',
			'--licenses',
			'<',
			'"' + yes_file + '""',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run_raw(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
	}

	item := opt.item

	opt.verbose(1, 'installing ${opt.dep}: "${item}"...')

	install_cmd := $if windows {
		[
			'cmd /c',
			'""' + sdkmanager() + '"',
			'--sdk_root="${sdk.root()}"',
			'"${item}""',
		]
	} $else {
		[
			'yes',
			'|',
			sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"${item}"',
		]
	}

	match opt.dep {
		.bundletool {
			return ensure_bundletool(opt.verbosity)
		}
		.aapt2 {
			return ensure_aapt2(opt.verbosity)
		}
		.cmdline_tools, .platform_tools, .emulator, .system_images {
			util.verbosity_print_cmd(install_cmd, opt.verbosity)
			cmd_res := $if windows {
				util.run_raw(install_cmd)
			} $else {
				util.run(install_cmd)
			}
			if cmd_res.exit_code != 0 {
				return error(cmd_res.output)
			}
			return true
		}
		.ndk {
			version_check := item.all_after(';')
			if version_check != '' {
				sv_check := semver.from(version_check) or { panic(err) }
				comp_sv := semver.from(ndk.min_supported_version) or { panic(err) }
				if sv_check < comp_sv {
					vabutil.vab_notice('Skipping install. NDK ${item} is lower than supported ${ndk.min_supported_version}...')
					return true
				}
			}
			opt.verbose(1, 'Installing NDK (Side-by-side) "${item}"...')

			util.verbosity_print_cmd(install_cmd, opt.verbosity)
			cmd_res := $if windows {
				util.run_raw(install_cmd)
			} $else {
				util.run(install_cmd)
			}
			if cmd_res.exit_code != 0 {
				return error(cmd_res.output)
			}
			return true
		}
		.build_tools {
			version_check := item.all_after(';')
			if version_check != '' {
				sv_check := semver.from(version_check) or { panic(err) }
				comp_sv := semver.from(sdk.min_supported_build_tools_version) or { panic(err) }
				if sv_check < comp_sv {
					vabutil.vab_notice('Skipping install. build-tools "${item}" is lower than supported ${sdk.min_supported_build_tools_version}...')
					return true
				}
			}
			util.verbosity_print_cmd(install_cmd, opt.verbosity)
			cmd_res := $if windows {
				util.run_raw(install_cmd)
			} $else {
				util.run(install_cmd)
			}
			if cmd_res.exit_code != 0 {
				return error(cmd_res.output)
			}
			return true
		}
		.platforms {
			api_level := item.all_after('-')
			if api_level.i16() < sdk.min_supported_api_level.i16() {
				vabutil.vab_notice('Skipping install. platform ${item} is lower than supported android-${sdk.min_supported_api_level}...')
				return true
			}
			util.verbosity_print_cmd(install_cmd, opt.verbosity)
			cmd_res := $if windows {
				util.run_raw(install_cmd)
			} $else {
				util.run(install_cmd)
			}
			if cmd_res.exit_code != 0 {
				return error(cmd_res.output)
			}
			return true
		}
	}
	return error(@MOD + '.' + @FN + ' ' + 'unknown install type ${opt.dep}')
}

fn ensure_sdkmanager(verbosity int) !bool {
	// Android development is a complete mess. Struggles include things like:
	// * Ever changing tool locations
	// * Missing version info from tools
	// * Core tools living their life outside the SDK (bundletool, modified AAPT2)
	// * Inconsistent versions of tools between major/minor releases.
	// * ... and who doesn't remember the big compiler change from gcc to clang ...
	// For troubleshooting and info, please see
	// https://stackoverflow.com/a/58652345
	// https://stackoverflow.com/a/61176718
	// https://stackoverflow.com/questions/60727326
	if sdkmanager() == '' {
		// Let just cross fingers that it ends up where we want it.
		dst := os.join_path(sdk.cache_dir(), 'cmdline-tools')
		if verbosity > 0 {
			println('No `sdkmanager` found. Bootstrapping...')
		}
		def_components := get_default_components()!
		// Download
		uos := os.user_os().replace('windows', 'win').replace('macos', 'mac')
		url := def_components['cmdline-tools']['bootstrap_url'].replace('[XXX]', uos)
		file := os.join_path(os.temp_dir(), 'v-android-sdk-cmdltools.tmp.zip')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `sdkmanager` from "${url}"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download commandline tools needed for bootstrapping: ${err}')
			}
		}
		// Install
		if verbosity > 1 {
			println('Installing `sdkmanager` to "${dst}"...')
		}
		os.mkdir_all(dst)!
		mut dst_check := os.join_path(dst, 'tools', 'bin')

		util.unzip(file, dst)!
		if os.is_dir(os.join_path(dst, 'cmdline-tools', 'bin')) {
			fixed_path := os.join_path(dst, def_components['cmdline-tools']['version'])
			os.mv(os.join_path(dst, 'cmdline-tools'), fixed_path)!
			dst_check = os.join_path(fixed_path, 'bin')
			if verbosity > 1 {
				println('Fixed `cmdline-tools` path to "${fixed_path}"...')
			}
		}

		os.chmod(os.join_path(dst_check, 'sdkmanager'), 0o755)!

		if os.is_executable(os.join_path(dst_check, 'sdkmanager')) {
			$if linux {
				// Workaround BUG: Error: Could not find or load main class com.android.sdklib.tool.sdkmanager.SdkManagerCli
				jarrs := os.walk_ext(dst, '.jarr')
				for jarr in jarrs {
					file_no_ext := jarr.all_before_last('.')
					os.mv(jarr, file_no_ext + '.jar') or { panic(err) }
				}
			}
			util.run([os.join_path(dst_check, 'sdkmanager')])
			if verbosity > 1 {
				sdkm_version := sdkmanager_version()
				println('`sdkmanager` v${sdkm_version} installed in "${dst_check}". SDK root reports "${sdk.root()}"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' +
			'failed to install commandline tools to "${dst_check}".')
	}
	return false
}

fn ensure_bundletool(verbosity int) !bool {
	if bundletool() == '' {
		dst := util.cache_dir()
		if verbosity > 0 {
			println('No `bundletool` found. Bootstrapping...')
		}
		def_components := get_default_components()!
		// Download
		url := def_components['bundletool']['bootstrap_url']
		file := os.join_path(dst, 'bundletool.jar')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `bundletool` from "${url}"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download `bundletool` needed for aab support: ${err}')
			}
		}
		// Install
		dst_check := os.join_path(dst, 'bundletool.jar')
		if os.exists(dst_check) {
			if verbosity > 1 {
				println('`bundletool` installed in "${dst_check}"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install `bundletool` to "${dst_check}"')
	}
	return false
}

pub fn has_sdkmanager() bool {
	return sdkmanager() != ''
}

fn sdkmanager_windows() string {
	mut sdkmanager := cache.get_string(@MOD + '.' + @FN)
	if sdkmanager != '' {
		return sdkmanager
	}

	sdkmanager = os.getenv('SDKMANAGER')
	// Check in cache
	if !os.exists(sdkmanager) {
		sdkmanager = os.join_path(util.cache_dir(), 'sdkmanager.bat')
		if !os.exists(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', '3.0', 'bin',
				'sdkmanager.bat')
		}
		if !os.exists(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', '2.1', 'bin',
				'sdkmanager.bat')
		}
		if !os.exists(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', 'tools', 'bin',
				'sdkmanager.bat')
		}
	}
	// Try if one is in PATH
	if !os.exists(sdkmanager) {
		if os.exists_in_system_path('sdkmanager') {
			sdkmanager = os.find_abs_path_of_executable('sdkmanager') or { '' }
			sdkmanager = sdkmanager.trim_string_right('.bat') + '.bat'
		}
	}
	// Try detecting it in the SDK
	if sdk.found() {
		if !os.exists(sdkmanager) {
			sdkmanager = os.join_path(sdk.root(), 'cmdline-tools', 'tools', 'bin', 'sdkmanager.bat')
		}
		if !os.exists(sdkmanager) {
			sdkmanager = os.join_path(sdk.tools_root(), 'bin', 'sdkmanager.bat')
		}
		if !os.exists(sdkmanager) {
			for relative_path in possible_relative_to_sdk_sdkmanager_paths {
				sdkmanager = os.join_path(sdk.root(), relative_path, 'sdkmanager.bat')
				if os.exists(sdkmanager) {
					break
				}
			}
		}
		if !os.exists(sdkmanager) {
			version_dirs := util.ls_sorted(os.join_path(sdk.root(), 'cmdline-tools')).filter(fn (a string) bool {
				return util.is_version(a)
			})
			for version_dir in version_dirs {
				sdkmanager = os.join_path(sdk.root(), 'cmdline-tools', version_dir, 'bin',
					'sdkmanager.bat')
				if os.exists(sdkmanager) {
					break
				}
			}
		}
	}
	// Give up
	if !os.exists(sdkmanager) {
		sdkmanager = ''
	}
	cache.set_string(@MOD + '.' + @FN, sdkmanager)
	return sdkmanager
}

pub fn sdkmanager() string {
	$if windows {
		return sdkmanager_windows()
	}
	mut sdkmanager := cache.get_string(@MOD + '.' + @FN)
	if sdkmanager != '' {
		return sdkmanager
	}

	sdkmanager = os.getenv('SDKMANAGER')
	// Check in cache
	if !os.is_executable(sdkmanager) {
		sdkmanager = os.join_path(util.cache_dir(), 'sdkmanager')
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', '3.0', 'bin',
				'sdkmanager')
		}
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', '2.1', 'bin',
				'sdkmanager')
		}
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(sdk.cache_dir(), 'cmdline-tools', 'tools', 'bin',
				'sdkmanager')
		}
	}
	// Try if one is in PATH
	if !os.is_executable(sdkmanager) {
		if os.exists_in_system_path('sdkmanager') {
			sdkmanager = os.find_abs_path_of_executable('sdkmanager') or { '' }
		}
	}
	// Try detecting it in the SDK
	if sdk.found() {
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(sdk.root(), 'cmdline-tools', 'tools', 'bin', 'sdkmanager')
		}
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(sdk.tools_root(), 'bin', 'sdkmanager')
		}
		if !os.is_executable(sdkmanager) {
			for relative_path in possible_relative_to_sdk_sdkmanager_paths {
				sdkmanager = os.join_path(sdk.root(), relative_path, 'sdkmanager')
				if os.is_executable(sdkmanager) {
					break
				}
			}
		}
		if !os.is_executable(sdkmanager) {
			version_dirs := util.ls_sorted(os.join_path(sdk.root(), 'cmdline-tools')).filter(fn (a string) bool {
				return util.is_version(a)
			})
			for version_dir in version_dirs {
				sdkmanager = os.join_path(sdk.root(), 'cmdline-tools', version_dir, 'bin',
					'sdkmanager')
				if os.is_executable(sdkmanager) {
					break
				}
			}
		}
	}
	// Give up
	if !os.is_executable(sdkmanager) {
		sdkmanager = ''
	}
	cache.set_string(@MOD + '.' + @FN, sdkmanager)
	return sdkmanager
}

pub fn sdkmanager_version() string {
	sdkm := sdkmanager()
	mut version := cache.get_string(@MOD + '.' + @FN + sdkm)
	if version != '' {
		return version
	}
	version = '0.0.0'
	if sdkm != '' {
		cmd := [
			sdkm,
			'--version',
		]
		cmd_res := util.run(cmd)
		if cmd_res.exit_code != 0 {
			cache.set_string(@MOD + '.' + @FN + sdkm, version)
			return version
		}
		// sdkmanager can be... Uhm.. noisy and using os.Process can hang the CI...
		// So to work around this we try to find a version string in a more
		// primitive way
		for raw_line in cmd_res.output.split('\n') {
			line := raw_line.trim_space()
			if !line.contains('.') {
				continue
			}
			vs := line.split('.')
			if vs.len < 2 {
				continue
			}
			for b in vs[0] {
				if !b.is_digit() {
					break
				}
			}
			for b in vs[1] {
				if !b.is_digit() {
					break
				}
			}
			version = line
		}
	}
	cache.set_string(@MOD + '.' + @FN + sdkm, version)
	return version
}

pub fn has_adb() bool {
	adb_path := adb()
	return adb_path != '' && os.is_executable(adb_path)
}

// adb returns the full path to the `adb` tool, if found. An empty string otherwise.
pub fn adb() string {
	mut adb_path := os.getenv('ADB')
	if !os.exists(adb_path) {
		adb_path = os.join_path(sdk.platform_tools_root(), 'adb${dot_exe}')
	}
	if !os.exists(adb_path) {
		if os.exists_in_system_path('adb') {
			adb_path = os.find_abs_path_of_executable('adb') or { '' }
			if adb_path != '' {
				// adb normally reside in 'path/to/sdk_root/platform-tools/'
				adb_path = os.real_path(os.join_path(os.dir(adb_path), '..'))
			}
		}
	}
	return adb_path
}

// has_avdmanager returns `true` if `avdmanager` can be located on the system.
pub fn has_avdmanager() bool {
	return avdmanager() != ''
}

// avdmanager returns the full path to the `avdmanager` tool, if found. An empty string otherwise.
pub fn avdmanager() string {
	mut avdmanager_exe := cache.get_string(@MOD + '.' + @FN)
	if avdmanager_exe != '' {
		return avdmanager_exe
	}

	avdmanager_exe = os.getenv('AVDMANAGER')
	// Check in cache
	if !os.is_executable(avdmanager_exe) {
		avdmanager_exe = os.join_path(util.cache_dir(), 'avdmanager')
		if !os.is_executable(avdmanager_exe) {
			avdmanager_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', '3.0', 'bin',
				'avdmanager')
		}
		if !os.is_executable(avdmanager_exe) {
			avdmanager_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', '2.1', 'bin',
				'avdmanager')
		}
		if !os.is_executable(avdmanager_exe) {
			avdmanager_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', 'tools', 'bin',
				'avdmanager')
		}
	}
	// Try if one is in PATH
	if !os.is_executable(avdmanager_exe) {
		if os.exists_in_system_path('avdmanager') {
			avdmanager_exe = os.find_abs_path_of_executable('avdmanager') or { '' }
		}
	}
	// Try detecting it in the SDK
	if sdk.found() {
		if !os.is_executable(avdmanager_exe) {
			avdmanager_exe = os.join_path(sdk.root(), 'cmdline-tools', 'tools', 'bin',
				'avdmanager')
		}
		if !os.is_executable(avdmanager_exe) {
			avdmanager_exe = os.join_path(sdk.tools_root(), 'bin', 'avdmanager')
		}
		// It's often found next to `sdkmanager`
		if !os.is_executable(avdmanager_exe) {
			for relative_path in possible_relative_to_sdk_sdkmanager_paths {
				avdmanager_exe = os.join_path(sdk.root(), relative_path, 'avdmanager')
				if os.is_executable(avdmanager_exe) {
					break
				}
			}
		}
		if !os.is_executable(avdmanager_exe) {
			version_dirs := util.ls_sorted(os.join_path(sdk.root(), 'cmdline-tools')).filter(fn (a string) bool {
				return util.is_version(a)
			})
			for version_dir in version_dirs {
				avdmanager_exe = os.join_path(sdk.root(), 'cmdline-tools', version_dir,
					'bin', 'avdmanager')
				if os.is_executable(avdmanager_exe) {
					break
				}
			}
		}
	}
	// Give up
	if !os.is_executable(avdmanager_exe) {
		avdmanager_exe = ''
	}
	cache.set_string(@MOD + '.' + @FN, avdmanager_exe)
	return avdmanager_exe
}

// emulator returns the full path to the `emulator` tool, if found. An empty string otherwise.
pub fn emulator() string {
	mut emulator_exe := cache.get_string(@MOD + '.' + @FN)
	if emulator_exe != '' {
		return emulator_exe
	}

	emulator_exe = os.getenv('EMULATOR')
	// Check in cache
	if !os.is_executable(emulator_exe) {
		emulator_exe = os.join_path(util.cache_dir(), 'emulator${dot_exe}')
		if !os.is_executable(emulator_exe) {
			emulator_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', '3.0', 'bin',
				'emulator${dot_exe}')
		}
		if !os.is_executable(emulator_exe) {
			emulator_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', '2.1', 'bin',
				'emulator${dot_exe}')
		}
		if !os.is_executable(emulator_exe) {
			emulator_exe = os.join_path(sdk.cache_dir(), 'cmdline-tools', 'tools', 'bin',
				'emulator${dot_exe}')
		}
	}
	// Try if one is in PATH
	if !os.is_executable(emulator_exe) {
		if os.exists_in_system_path('emulator') {
			emulator_exe = os.find_abs_path_of_executable('emulator${dot_exe}') or { '' }
		}
	}
	// Try detecting it in the SDK
	if sdk.found() {
		if !os.is_executable(emulator_exe) {
			emulator_exe = os.join_path(sdk.root(), 'cmdline-tools', 'tools', 'bin', 'emulator${dot_exe}')
		}
		if !os.is_executable(emulator_exe) {
			emulator_exe = os.join_path(sdk.tools_root(), 'bin', 'emulator${dot_exe}')
		}
		// It's often found next to `sdkmanager`
		if !os.is_executable(emulator_exe) {
			for relative_path in possible_relative_to_sdk_sdkmanager_paths {
				emulator_exe = os.join_path(sdk.root(), relative_path, 'emulator${dot_exe}')
				if os.is_executable(emulator_exe) {
					break
				}
			}
		}
		if !os.is_executable(emulator_exe) {
			version_dirs := util.ls_sorted(os.join_path(sdk.root(), 'cmdline-tools')).filter(fn (a string) bool {
				return util.is_version(a)
			})
			for version_dir in version_dirs {
				emulator_exe = os.join_path(sdk.root(), 'cmdline-tools', version_dir,
					'bin', 'emulator${dot_exe}')
				if os.is_executable(emulator_exe) {
					break
				}
			}
		}
		if !os.exists(emulator_exe) {
			emulator_exe = os.join_path(sdk.root(), 'emulator', 'emulator${dot_exe}')
		}
	}
	// Give up
	if !os.is_executable(emulator_exe) {
		emulator_exe = ''
	}
	cache.set_string(@MOD + '.' + @FN, emulator_exe)
	return emulator_exe
}

// has_emulator returns `true` if `emulator` can be located on the system.
pub fn has_emulator() bool {
	return emulator() != ''
}

// has_bundletool returns `true` if `bundletool` can be located on the system.
pub fn has_bundletool() bool {
	return bundletool() != ''
}

pub fn bundletool() string {
	mut bundletool := os.getenv('BUNDLETOOL')
	if !os.exists(bundletool) {
		bundletool = os.join_path(util.cache_dir(), 'bundletool.jar')
	}
	// No fancy stuff right now
	/*
	// Check in cache
	if !os.is_executable(bundletool) {
		bundletool = os.join_path(util.cache_dir(), 'bundletool')
		if !os.is_executable(bundletool) {
			bundletool = os.join_path(util.cache_dir(), 'tools', 'bin', 'bundletool')
		}
	}
	// Try if one is in PATH
	if !os.is_executable(bundletool) {
		if os.exists_in_system_path('bundletool') {
			bundletool = os.find_abs_path_of_executable('bundletool') or { '' }
		}
	}
	// Try detecting it in the SDK
	if found() {
		if !os.is_executable(bundletool) {
			bundletool = os.join_path(root(), 'cmdline-tools', 'tools', 'bin', 'bundletool')
		}
		if !os.is_executable(bundletool) {
			bundletool = os.join_path(root(), 'bin', 'bundletool')
		}
		if !os.is_executable(bundletool) {
			version_dirs := util.ls_sorted(os.join_path(root(), 'cmdline-tools')).filter(fn (a string) bool {
				return util.is_version(a)
			})
			for version_dir in version_dirs {
				bundletool = os.join_path(root(), 'cmdline-tools', version_dir, 'bin',
					'bundletool')
				if os.is_executable(bundletool) {
					break
				}
			}
		}
	}
	*/
	// Give up
	if !os.exists(bundletool) {
		bundletool = ''
	}
	return bundletool
}

pub fn has_aapt2() bool {
	return aapt2() != ''
}

pub fn aapt2() string {
	mut aapt2 := os.getenv('AAPT2')
	if !os.exists(aapt2) {
		aapt2 = os.join_path(util.cache_dir(), 'aapt2${dot_exe}')
	}
	$if !windows {
		if !os.is_executable(aapt2) {
			aapt2 = ''
		}
	} $else {
		if !os.exists(aapt2) {
			aapt2 = ''
		}
	}
	return aapt2
}

fn ensure_aapt2(verbosity int) !bool {
	if aapt2() == '' {
		dst := util.cache_dir()
		if verbosity > 0 {
			println('No `aapt2` found. Bootstrapping...')
		}
		def_components := get_default_components()!
		// Download
		// https://maven.google.com/web/index.html -> com.android.tools.build -> aapt2
		uos := os.user_os().replace('macos', 'osx')
		url := def_components['aapt2']['bootstrap_url'].replace('[XXX]', uos)
		file := os.join_path(os.temp_dir(), 'aapt2.jar')
		// file := os.join_path(dst, 'aapt2.jar')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `aapt2` from "${url}"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download `aapt2` needed for aab support: ${err}')
			}
		}
		// Unpack
		unpack_path := os.join_path(os.temp_dir(), 'vab-aapt2')
		os.rmdir_all(unpack_path) or {}
		os.mkdir_all(unpack_path) or {
			return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2`: ${err}')
		}
		util.unzip(file, unpack_path)!
		aapt2_file := os.join_path(unpack_path, 'aapt2${dot_exe}')
		dst_check := os.join_path(dst, 'aapt2${dot_exe}')
		os.rm(dst_check) or {}
		os.cp(aapt2_file, dst_check) or {
			return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2${dot_exe}`: ${err}')
		}
		if os.exists(dst_check) {
			if verbosity > 1 {
				println('`aapt2` installed as "${dst_check}"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2` to "${dst_check}".')
	}
	return false
}
