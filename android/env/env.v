// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module env

import os
import semver
import net.http
import cache
import android.sdk
import android.ndk
import android.util

pub const (
	accepted_components = ['auto', 'cmdline-tools', 'platform-tools', 'ndk', 'platforms',
		'build-tools', 'bundletool', 'aapt2']
	// 6858069 = cmdline-tools;3.0 <- zip structure changes *sigh*
	// 6609375 = cmdline-tools;2.1 <- latest that support `sdkmanager --version` *sigh*
	// cmdline-tools-bootstrap-url - Replace {XXX} with linux/mac/win
	// cmdline-tools - Latest more or less sane version that works with java versions >= 8 ...
	// sdk - Latest
	// ndk - Works with android.compile(...)
	// platform - Google Play minimum
	// build-tools - Version where apksigner is included from
	default_components  = {
		'cmdline-tools':  {
			'name':          'cmdline-tools'
			'version':       '2.1'
			'bootstrap_url': 'https://dl.google.com/android/repository/commandlinetools-{XXX}-6609375_latest.zip'
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
			'bootstrap_url': 'https://dl.google.com/android/maven2/com/android/tools/build/aapt2/7.0.0-alpha07-7087017/aapt2-7.0.0-alpha07-7087017-{XXX}.jar'
		}
	}
)

// Possible locations of the `sdkmanager` tool
// https://stackoverflow.com/a/61176718
const (
	possible_relative_to_sdk_sdkmanager_paths = [
		os.join_path('cmdline-tools', 'latest', 'bin'),
		os.join_path('tools', 'latest', 'bin'),
		os.join_path('cmdline-tools', 'tools', 'bin'),
		os.join_path('tools', 'bin'),
	]
)

pub enum Dependency {
	platform_tools
	ndk
	platforms
	build_tools
	cmdline_tools
	bundletool
	aapt2
}

pub struct InstallOptions {
	dep       Dependency
	item      string
	verbosity int
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

pub fn install(components string, verbosity int) int {
	mut ios := []InstallOptions{}
	mut ensure_sdk := true
	// Allows to specify a string list of things to install
	components_array := components.split(',')
	for comp in components_array {
		mut component := comp
		mut version := ''
		is_auto := component.contains('auto')

		if !is_auto {
			version = env.default_components[component]['version'] // Set default version
			if component.contains(';') { // If user has specified a version, use that
				cs := component.split(';')
				component = cs.first()
				version = cs.last()
			}
		}

		if component !in env.accepted_components {
			eprintln(@MOD + ' ' + @FN + ' component "$component" not recognized.')
			eprintln('Available components ${env.accepted_components}.')
			return 1
		}

		if !is_auto && version == '' {
			eprintln(@MOD + ' ' + @FN + ' install component "$component" has no version.')
			return 1
		}

		item := if version != '' { component + ';' + version } else { component }

		match component {
			'auto' {
				cmdline_tools_comp := env.default_components['cmdline-tools']['name'] + ';' +
					env.default_components['cmdline-tools']['version']
				platform_tools_comp := env.default_components['platform-tools']['name'] //+ ';' + env.default_components['platform-tools']['version']
				ndk_comp := env.default_components['ndk']['name'] + ';' +
					env.default_components['ndk']['version']
				build_tools_comp := env.default_components['build-tools']['name'] + ';' +
					env.default_components['build-tools']['version']
				platforms_comp := env.default_components['platforms']['name'] + ';' +
					env.default_components['platforms']['version']
				ios = [
					InstallOptions{.cmdline_tools, cmdline_tools_comp, verbosity},
					InstallOptions{.platform_tools, platform_tools_comp, verbosity},
					InstallOptions{.ndk, ndk_comp, verbosity},
					InstallOptions{.build_tools, build_tools_comp, verbosity},
					InstallOptions{.platforms, platforms_comp, verbosity},
				]
				break
			}
			'cmdline-tools' {
				ios << InstallOptions{.cmdline_tools, item, verbosity}
			}
			'platform-tools' {
				ios << InstallOptions{.platform_tools, item, verbosity}
			}
			'ndk' {
				ios << InstallOptions{.ndk, item, verbosity}
			}
			'build-tools' {
				ios << InstallOptions{.build_tools, item, verbosity}
			}
			'platforms' {
				ios << InstallOptions{.platforms, item, verbosity}
			}
			'bundletool' {
				ensure_sdk = false
				ios << InstallOptions{.bundletool, item, verbosity}
			}
			'aapt2' {
				ensure_sdk = false
				ios << InstallOptions{.aapt2, item, verbosity}
			}
			else {
				eprintln(@MOD + ' ' + @FN + ' unknown component "$component"')
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

	for io in ios {
		install_opt(io) or {
			eprintln(err)
			return 1
		}
	}
	return 0
}

fn install_opt(opt InstallOptions) ?bool {
	loose := opt.dep == .bundletool || opt.dep == .aapt2

	if !loose && !managable() {
		if !os.is_writable(sdk.root()) {
			return error(@MOD + '.' + @FN + ' ' +
				'No permission to write in Android SDK root. Please install manually or ensure write access to "$sdk.root()".')
		} else {
			return error(@MOD + '.' + @FN + ' ' +
				'The `sdkmanager` seems outdated or incompatible with the Java version used". Please fix your setup manually.')
		}
	}

	item := opt.item

	mut yes_cmd := 'yes' // Linux / macOS
	$if windows {
		yes_cmd = 'echo y' // Windows PowerShell
	}

	// TODO - right now, because of tricky shell escaping, Windows users need to manually
	// run the install commands
	if opt.verbosity > 0 {
		println(@MOD + '.' + @FN + ' installing $opt.dep: "$item"...')
	}
	if opt.dep == .bundletool {
		return ensure_bundletool(opt.verbosity)
	} else if opt.dep == .aapt2 {
		return ensure_aapt2(opt.verbosity)
	} else if opt.dep == .cmdline_tools {
		cmd := [
			yes_cmd + ' |' /* TODO Windows */,
			sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"$item"',
		]
		$if !windows {
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		} $else {
			return error('Run the following command in your shell to install "$item":\n' +
				cmd.join(' '))
		}
	} else if opt.dep == .platform_tools {
		// Ignore opt.item for now
		cmd := [
			yes_cmd + ' |' /* TODO Windows */,
			sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"$item"',
		]
		$if !windows {
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		} $else {
			return error('Run the following command in your shell to install "$item":\n' +
				cmd.join(' '))
		}
	} else if opt.dep == .ndk {
		version_check := item.all_after(';')
		if version_check != '' {
			sv_check := semver.from(version_check) or { panic(err) }
			comp_sv := semver.from(ndk.min_supported_version) or { panic(err) }
			if sv_check.lt(comp_sv) {
				eprintln('Notice: Skipping install. NDK $item is lower than supported ${ndk.min_supported_version}...')
				return true
			}
		}

		if opt.verbosity > 0 {
			println('Installing NDK (Side-by-side) "$item"...')
		}
		cmd := [
			yes_cmd + ' |' /* TODO Windows */,
			sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"$item"',
		]
		$if !windows {
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		} $else {
			return error('Run the following command in your shell to install "$item":\n' +
				cmd.join(' '))
		}
	} else if opt.dep == .build_tools {
		version_check := item.all_after(';')
		if version_check != '' {
			sv_check := semver.from(version_check) or { panic(err) }
			comp_sv := semver.from(sdk.min_supported_build_tools_version) or { panic(err) }
			if sv_check.lt(comp_sv) {
				eprintln('Notice: Skipping install. build-tools "$item" is lower than supported ${sdk.min_supported_build_tools_version}...')
				return true
			}
		}

		cmd := [
			yes_cmd + ' |' /* TODO Windows */,
			sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"$item"',
		]

		$if !windows {
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		} $else {
			return error('Run the following command in your shell to install "$item":\n' +
				cmd.join(' '))
		}
	} else if opt.dep == .platforms {
		v := item.all_after('-')
		if v.i16() < sdk.min_supported_api_level.i16() {
			eprintln('Notice: Skipping install. platform $item is lower than supported android-${sdk.min_supported_api_level}...')
			return true
		}

		cmd := [
			yes_cmd + ' |' /* TODO Windows */,
			sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"$item"',
		]
		$if !windows {
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		} $else {
			/*return error('Run the following command in your shell to install "$item":\n' +
				cmd.join(' '))*/
			util.verbosity_print_cmd(cmd, opt.verbosity)
			cmd_res := util.run(cmd)
			if cmd_res.exit_code > 0 {
				return error(cmd_res.output)
			}
			return true
		}
	}
	return error(@MOD + '.' + @FN + ' ' + 'unknown install type $opt.dep')
}

fn ensure_sdkmanager(verbosity int) ?bool {
	// Android development is a complete mess. Struggles include things like:
	// * Ever changing tool locations
	// * Missing version info from tools
	// * Core tools living their life outside the SDK (bundletool, modified AAPT2)
	// * Inconsistent versions of tools between major/minor releases.
	// * ... and who doesn't remember the big compiler change from gcc to clang ...
	// For troubleshooting and info, please see
	// https://stackoverflow.com/a/58652345
	// https://stackoverflow.com/a/61176718
	if sdkmanager() == '' {
		// Let just cross fingers that it ends up where we want it.
		dst := os.join_path(sdk.cache_dir(), 'cmdline-tools')
		if verbosity > 0 {
			println('No `sdkmanager` found. Bootstrapping...')
		}
		// Download
		uos := os.user_os().replace('windows', 'win').replace('macos', 'mac')
		url := env.default_components['cmdline-tools']['bootstrap_url'].replace('{XXX}',
			uos)
		file := os.join_path(os.temp_dir(), 'v-android-sdk-cmdltools.tmp.zip')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `sdkmanager` from "$url"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download commandline tools needed for bootstrapping: $err')
			}
		}
		// Install
		if verbosity > 1 {
			println('Installing `sdkmanager` to "$dst"...')
		}
		os.mkdir_all(dst) or { panic(err) }
		dst_check := os.join_path(dst, 'tools', 'bin')
		if util.unzip(file, dst) {
			os.chmod(os.join_path(dst_check, 'sdkmanager'), 0o755) or { panic(err) }
		}
		if os.is_executable(os.join_path(dst_check, 'sdkmanager')) {
			if verbosity > 1 {
				println('`sdkmanager` installed in "$dst_check". SDK root reports "$sdk.root()"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install commandline tools to "$dst_check".')
	}
	return false
}

fn ensure_bundletool(verbosity int) ?bool {
	if bundletool() == '' {
		dst := util.cache_dir()
		if verbosity > 0 {
			println('No `bundletool` found. Bootstrapping...')
		}
		// Download
		url := env.default_components['bundletool']['bootstrap_url']
		file := os.join_path(dst, 'bundletool.jar')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `bundletool` from "$url"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download `bundletool` needed for aab support: $err')
			}
		}
		// Install
		dst_check := os.join_path(dst, 'bundletool.jar')
		if os.exists(dst_check) {
			if verbosity > 1 {
				println('`bundletool` installed in "$dst_check"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install `bundletool` to "$dst_check"')
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
			for relative_path in env.possible_relative_to_sdk_sdkmanager_paths {
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
			for relative_path in env.possible_relative_to_sdk_sdkmanager_paths {
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
	mut version := '0.0.0'
	sdkm := sdkmanager()
	if sdkm != '' {
		cmd := [
			sdkm,
			'--version',
		]
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return version
		}
		version = cmd_res.output.trim(' \n\r')
	}
	return version
}

pub fn has_adb() bool {
	return adb() != ''
}

pub fn adb() string {
	mut adb_path := os.getenv('ADB')
	if !os.exists(adb_path) {
		adb_path = os.join_path(sdk.platform_tools_root(), 'adb')
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
		aapt2 = os.join_path(util.cache_dir(), 'aapt2')
	}
	if !os.is_executable(aapt2) {
		aapt2 = ''
	}
	return aapt2
}

fn ensure_aapt2(verbosity int) ?bool {
	if aapt2() == '' {
		dst := util.cache_dir()
		if verbosity > 0 {
			println('No `aapt2` found. Bootstrapping...')
		}
		// Download
		// https://maven.google.com/web/index.html -> com.android.tools.build -> aapt2
		uos := os.user_os().replace('windows', 'win').replace('macos', 'osx')
		url := env.default_components['aapt2']['bootstrap_url'].replace('{XXX}', uos)
		file := os.join_path(os.temp_dir(), 'aapt2.jar')
		// file := os.join_path(dst, 'aapt2.jar')
		if !os.exists(file) {
			if verbosity > 1 {
				println('Downloading `aapt2` from "$url"...')
			}
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download `aapt2` needed for aab support: $err')
			}
		}
		// Unpack
		unpack_path := os.join_path(os.temp_dir(), 'vab-aapt2')
		os.rmdir_all(unpack_path) or {}
		os.mkdir_all(unpack_path) or {
			return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2`: $err')
		}
		util.unzip(file, unpack_path)
		// Install
		aapt2_file := os.join_path(unpack_path, 'aapt2')
		dst_check := os.join_path(dst, 'aapt2')
		os.rm(dst_check) or {}
		os.cp(aapt2_file, dst_check) or {
			return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2`: $err')
		}
		if os.exists(dst_check) {
			if verbosity > 1 {
				println('`aapt2` installed in "$dst_check"')
			}
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install `aapt2` to "$dst_check".')
	}
	return false
}
