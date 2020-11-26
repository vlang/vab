// Copyright(C) 2019 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module env

import os
import net.http

import android.sdk
import android.ndk
import android.util
import semver

pub const (
	accepted_components = ['auto','tools', 'sdk', 'ndk','platform','build-tools']
	default_components = {
		'tools':'https://dl.google.com/android/repository/commandlinetools-{XXX}-6609375_latest.zip' // Replace {XXX} with linux/mac/win
		'sdk':'platform-tools',								// Latest
		'ndk':ndk.min_supported_version,					// Works with android.compile(...)
		'platform':'android-'+sdk.min_supported_api_level	// Google Play minimum
		'build-tools':sdk.min_supported_build_tools_version,// Version where apksigner is included from
	}
)

pub enum Dependency {
	tools
	sdk
	ndk
	platform
	build_tools
}

pub struct InstallOptions {
	dep			Dependency
	version		string
	verbosity	int
}

pub fn can_install() bool {
	return os.is_writable(sdk.root())
}

pub fn install(components string, verbosity int) int {
	mut ios := []InstallOptions{}

	components_array := components.split(',')
	for comp in components_array {
		mut component := comp
		mut version := ''
		is_auto := component.contains('auto')

		if !is_auto {
			version = default_components[component]
			if component.contains(';') {
				cs := component.split(';')
				component = cs.first()
				version = cs.last()
			}
		}

		if !(component in accepted_components) {
			eprintln(@MOD+' '+@FN+' install component "${component}" not recognized.')
			eprintln('Available components ${accepted_components}.')
			return 1
		}

		if !is_auto && version == '' {
			eprintln(@MOD+' '+@FN+' install component "${component}" has no version.')
			return 1
		}

		match component {
			'auto' {
				ios = [
					InstallOptions{.tools,default_components['tools'],verbosity},
					InstallOptions{.sdk,default_components['sdk'],verbosity},
					InstallOptions{.ndk,default_components['ndk'],verbosity},
					InstallOptions{.build_tools,default_components['build-tools'],verbosity},
					InstallOptions{.platform,default_components['platform'],verbosity}
				]
				break
			}
			'tools' {
				ios << InstallOptions{.tools,version,verbosity}
			}
			'sdk' {
				ios << InstallOptions{.sdk,version,verbosity}
			}
			'ndk' {
				ios << InstallOptions{.ndk,version,verbosity}
			}
			'build-tools' {
				ios << InstallOptions{.build_tools,version,verbosity}
			}
			'platform' {
				ios << InstallOptions{.platform,version,verbosity}
			}
			else {
				eprintln(@MOD+' '+@FN+' unknown component "${component}"')
				return 1
			}
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
	if opt.dep != .tools && !can_install() {
		return error(@MOD+'.'+@FN+' '+'No permission to write in Android SDK root "${sdk.root()}". Please install manually.')
	}
	if opt.verbosity > 0 {
		println(@MOD+'.'+@FN+' installing ${opt.dep} ${opt.version}...')
	}
	if opt.dep == .tools {
		dst := os.join_path(util.cache_dir(),'cmdline-tools')
		dst_check := os.join_path(dst,'tools','bin')
		if sdk.sdkmanager() == '' {
			// Ignore opt.version for now
			file := download(opt) or {
				return error(err)
			}
			os.mkdir_all(dst)
			if util.unzip(file,dst) {
				os.chmod(os.join_path(dst_check,'sdkmanager'), 0o755)
			}
			if os.is_executable(os.join_path(dst_check,'sdkmanager')) {
				return true
			}
			return error(@MOD+'.'+@FN+' '+'failed to install commandline tools in ${dst_check}.')

		} else {
			if opt.verbosity > 0 {
				println(@MOD+'.'+@FN+' '+'commandline tools is already installed.')
			}
			return true
		}
	} else if opt.dep == .sdk {
		adb := os.join_path(sdk.platform_tools_root(),'adb')
		if os.is_executable(adb) {
			eprintln('Notice: Skipping install. Platform Tools seem to be installed in "${sdk.platform_tools_root()}"...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing Platform Tools...')
		}
		// Ignore opt.version for now
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"platform-tools"'
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
			eprintln('Notice: Skipping install. NDK ${opt.version} is lower than supported ${ndk.min_supported_version}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "NDK (Side-by-side) ${opt.version}"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"ndk;${opt.version}"'
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
			eprintln('Notice: Skipping install. build-tools ${opt.version} is lower than supported ${sdk.min_supported_build_tools_version}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "build-tools ${opt.version}"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"build-tools;${opt.version}"'
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
			eprintln('Notice: Skipping install. platform ${opt.version} is lower than supported android-${sdk.min_supported_api_level}...')
			return true
		}

		if opt.verbosity > 0 {
			println('Installing "${opt.version}"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"platforms;${opt.version}"'
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	}
	return error(@MOD+'.'+@FN+' '+'unknown install type ${opt.dep}')
}

fn download(opt InstallOptions) ?string {
	if opt.dep == .tools {
		uos := os.user_os().replace('windows','win').replace('macos','mac')
		url := default_components['tools'].replace('{XXX}',uos)
		dst := os.join_path(os.temp_dir(),'v-android-sdk-cmdltools.zip')
		if os.exists(dst) {
			return dst
		}
		if http.download_file(url,dst) {
			return dst
		}
		return ''
	}
	return ''
}
