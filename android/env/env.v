// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module env

import os
import net.http
import android.sdk
import android.ndk
import android.util
import semver

pub const (
	accepted_components = ['auto', 'cmdline-tools', 'sdk', 'ndk', 'platform', 'build-tools']
	// 6858069 = cmdline-tools;3.0 <- zip structure changes *sigh*
	// 6609375 = cmdline-tools;2.1 <- latest that support `sdkmanager --version` *sigh*
	// cmdline-tools-bootstrap-url - Replace {XXX} with linux/mac/win
	// cmdline-tools - Latest more or less sane version that works with java versions >= 8 ...
	// sdk - Latest
	// ndk - Works with android.compile(...)
	// platform - Google Play minimum
	// build-tools - Version where apksigner is included from
	default_components  = {
		'cmdline-tools-bootstrap-url': 'https://dl.google.com/android/repository/commandlinetools-{XXX}-6609375_latest.zip'
		'cmdline-tools':               '2.1'
		'sdk':                         'platform-tools'
		'ndk':                         ndk.min_supported_version
		'platform':                    'android-' + sdk.min_supported_api_level
		'build-tools':                 sdk.min_supported_build_tools_version
	}
)

pub enum Dependency {
	sdk
	ndk
	platform
	build_tools
	cmdline_tools
}

pub struct InstallOptions {
	dep       Dependency
	version   string
	verbosity int
}

pub fn managable() bool {
	sdk_is_writable := os.is_writable(sdk.root())
	// sdkmanager checks
	sdkm := sdk.sdkmanager()
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
	// Allows to specify a string list of things to install
	components_array := components.split(',')
	for comp in components_array {
		mut component := comp
		mut version := ''
		is_auto := component.contains('auto')

		if !is_auto {
			version = env.default_components[component] // Set default version
			if component.contains(';') { // If user has specified a version, use that
				cs := component.split(';')
				component = cs.first()
				version = cs.last()
			}
		}

		if !(component in env.accepted_components) {
			eprintln(@MOD + ' ' + @FN + ' install component "$component" not recognized.')
			eprintln('Available components ${env.accepted_components}.')
			return 1
		}

		if !is_auto && version == '' {
			eprintln(@MOD + ' ' + @FN + ' install component "$component" has no version.')
			return 1
		}

		match component {
			'auto' {
				ios = [
					InstallOptions{.cmdline_tools, env.default_components['cmdline-tools'], verbosity},
					InstallOptions{.sdk, env.default_components['sdk'], verbosity},
					InstallOptions{.ndk, env.default_components['ndk'], verbosity},
					InstallOptions{.build_tools, env.default_components['build-tools'], verbosity},
					InstallOptions{.platform, env.default_components['platform'], verbosity},
				]
				break
			}
			'cmdline-tools' {
				ios << InstallOptions{.cmdline_tools, version, verbosity}
			}
			'sdk' {
				ios << InstallOptions{.sdk, version, verbosity}
			}
			'ndk' {
				ios << InstallOptions{.ndk, version, verbosity}
			}
			'build-tools' {
				ios << InstallOptions{.build_tools, version, verbosity}
			}
			'platform' {
				ios << InstallOptions{.platform, version, verbosity}
			}
			else {
				eprintln(@MOD + ' ' + @FN + ' unknown component "$component"')
				return 1
			}
		}
	}

	ensure(verbosity) or {
		eprintln(err)
		return 1
	}

	for io in ios {
		install_opt(io) or {
			eprintln(err)
			return 1
		}
	}
	return 0
}

fn ensure(verbosity int) ?bool {
	// Android development is a complete mess. Struggles include things like:
	// * Ever changing tool locations
	// * Missing version info from tools
	// * Inconsistent versions of tools between major releases.
	// * Who doesn't remember the big compiler change from gcc to clang ...
	// For troubleshooting and info, please see
	// https://stackoverflow.com/a/58652345
	// https://stackoverflow.com/a/61176718
	if sdk.sdkmanager() == '' {
		// Let just cross fingers that it ends up where we want it.
		dst := os.join_path(util.cache_dir(), 'cmdline-tools')
		if verbosity > 0 {
			println('No `sdkmanageer` found. Bootstrapping...')
		}
		// Download
		uos := os.user_os().replace('windows', 'win').replace('macos', 'mac')
		url := env.default_components['cmdline-tools-bootstrap-url'].replace('{XXX}',
			uos)
		file := os.join_path(os.temp_dir(), 'v-android-sdk-cmdltools.tmp.zip')
		if !os.exists(file) {
			http.download_file(url, file) or {
				return error(@MOD + '.' + @FN + ' ' +
					'failed to download commandline tools needed for bootstrapping: $err')
			}
		}
		// Install
		os.mkdir_all(dst) or { panic(err) }
		dst_check := os.join_path(dst, 'tools', 'bin')
		if util.unzip(file, dst) {
			os.chmod(os.join_path(dst_check, 'sdkmanager'), 0o755)
		}
		if os.is_executable(os.join_path(dst_check, 'sdkmanager')) {
			return true
		}
		return error(@MOD + '.' + @FN + ' ' + 'failed to install commandline tools to ${dst_check}.')
	}
	return false
}

fn install_opt(opt InstallOptions) ?bool {
	if opt.dep != .cmdline_tools && !managable() {
		if !os.is_writable(sdk.root()) {
			return error(@MOD + '.' + @FN + ' ' +
				'No permission to write in Android SDK root. Please install manually or ensure write access to "$sdk.root()".')
		} else {
			return error(@MOD + '.' + @FN + ' ' +
				'The `sdkmanager` seems outdated or incompatible with the Java version used". Please fix your setup manually.')
		}
	}
	if opt.verbosity > 0 {
		println(@MOD + '.' + @FN + ' installing $opt.dep ${opt.version}...')
	}
	if opt.dep == .cmdline_tools {
		if opt.verbosity > 0 {
			println(@MOD + '.' + @FN + ' ' +
				'commandline tools is already installed in "$sdk.sdkmanager()".')
		}
		if opt.verbosity > 0 {
			println('Installing "Commandline Tools $opt.version"...')
		}
		cmd := [
			'yes |' /* TODO Windows */,
			sdk.sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"cmdline-tools;$opt.version"',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .sdk {
		adb := os.join_path(sdk.platform_tools_root(), 'adb')
		if os.is_executable(adb) {
			eprintln('Notice: Skipping install. Platform Tools seem to be installed in "$sdk.platform_tools_root()"...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing Platform Tools...')
		}
		// Ignore opt.version for now
		cmd := [
			'yes |' /* TODO Windows */,
			sdk.sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"platform-tools"',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .ndk {
		sv := semver.from(opt.version) or { panic(err) }
		comp_sv := semver.from(ndk.min_supported_version) or { panic(err) }
		if sv.lt(comp_sv) {
			eprintln('Notice: Skipping install. NDK $opt.version is lower than supported ${ndk.min_supported_version}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "NDK (Side-by-side) $opt.version"...')
		}
		cmd := [
			'yes |' /* TODO Windows */,
			sdk.sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"ndk;$opt.version"',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .build_tools {
		sv := semver.from(opt.version) or { panic(err) }
		comp_sv := semver.from(sdk.min_supported_build_tools_version) or { panic(err) }
		if sv.lt(comp_sv) {
			eprintln('Notice: Skipping install. build-tools $opt.version is lower than supported ${sdk.min_supported_build_tools_version}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "build-tools $opt.version"...')
		}
		cmd := [
			'yes |' /* TODO Windows */,
			sdk.sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"build-tools;$opt.version"',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .platform {
		v := opt.version.all_after('-')
		if v.i16() < sdk.min_supported_api_level.i16() {
			eprintln('Notice: Skipping install. platform $opt.version is lower than supported android-${sdk.min_supported_api_level}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "$opt.version"...')
		}
		cmd := [
			'yes |' /* TODO Windows */,
			sdk.sdkmanager(),
			'--sdk_root="$sdk.root()"',
			'"platforms;$opt.version"',
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	}
	return error(@MOD + '.' + @FN + ' ' + 'unknown install type $opt.dep')
}
