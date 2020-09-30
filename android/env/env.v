module env

import os
import net.http

import android.sdk
import android.util

pub const (
	accepted_components = ['auto','tools', 'sdk', 'ndk','platform','build-tools']
	default_components = {
		'tools':'https://dl.google.com/android/repository/commandlinetools-{XXX}-6609375_latest.zip' // Replace {XXX} with linux/mac/win
		'sdk':'platform-tools',	// Latest
		'ndk':'21.1.6352462',	// Because it works with android.compile(...)
		'platform':'android-29'	// Google Play minimum
		'build-tools':'24.0.3',	// Version where apksigner is included from
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
	verbosity	int
}

pub fn can_install() bool {
	return os.is_writable(sdk.root())
}

pub fn install(components string, verbosity int) int {
	mut ios := []InstallOptions{}

	components_array := components.split(',')
	for component in components_array {
		if !(component in accepted_components) {
			eprintln(@MOD+' '+@FN+' install component "${component}" not recognized.')
			eprintln('Available components ${accepted_components}.')
			return 1
		}

		match component {
			'auto' {
				ios = [
					InstallOptions{.tools,verbosity},
					InstallOptions{.sdk,verbosity},
					InstallOptions{.ndk,verbosity},
					InstallOptions{.build_tools,verbosity},
					InstallOptions{.platform,verbosity}
				]
				break
			}
			'tools' {
				ios << InstallOptions{.tools,verbosity}
			}
			'sdk' {
				ios << InstallOptions{.sdk,verbosity}
			}
			'ndk' {
				ios << InstallOptions{.ndk,verbosity}
			}
			'build-tools' {
				ios << InstallOptions{.build_tools,verbosity}
			}
			'platform' {
				ios << InstallOptions{.platform,verbosity}
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
	if !can_install() {
		return error(@MOD+'.'+@FN+' '+'No permission to write in Android SDK root "${sdk.root()}". Please install manually.')
	}
	if opt.dep == .tools {
		dst := os.join_path(util.cache_dir(),'cmdline-tools')
		dst_check := os.join_path(dst,'tools','bin')
		if sdk.sdkmanager() == '' {
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
			return error(@MOD+'.'+@FN+' '+'failed to install commandline tools in ${dst_check}')

		} else {
			if opt.verbosity > 0 {
				println(@MOD+'.'+@FN+' '+'commandline tools is already installed in ${dst_check}')
				return true
			}
		}
	} else if opt.dep == .sdk {
		if opt.verbosity > 0 {
			println('Installing Latest SDK Platform Tools...')
		}
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
		if opt.verbosity > 0 {
			println('Installing "NDK (Side-by-side) 21.1.6352462"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"ndk;21.1.6352462"'
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .build_tools {
		if opt.verbosity > 0 {
			println('Installing "build-tools 24.0.3"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"build-tools;24.0.3"'
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return error(cmd_res.output)
		}
		return true
	} else if opt.dep == .platform {
		if opt.verbosity > 0 {
			println('Installing "android-29"...')
		}
		cmd := [
			'yes |' // TODO Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"platforms;android-29"'
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
