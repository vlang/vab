module env

import os
import net.http

import android.sdk
import android.util

pub enum Dependency {
	commandline_tools
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

pub fn install(opt InstallOptions) ?bool {
	if !can_install() {
		return error(@MOD+'.'+@FN+' '+'No permission to write in Android SDK root "${sdk.root()}". Please install manually.')
	}
	if opt.dep == .commandline_tools {
		cmdl_root := root_for(opt.dep)
		if cmdl_root != '' {
			return error(@MOD+'.'+@FN+' '+'commandline tools is already installed in ${cmdl_root}')
		}

		file := download(opt)
		if file == '' {
			return error(@MOD+'.'+@FN+' '+'downloading commandline tools failed')
		}
		unzip_dst := os.join_path(dependency_dir(opt.dep))
		os.mkdir_all(unzip_dst)
		if util.unzip(file,unzip_dst) {
			os.chmod(os.join_path(cmdl_root,'sdkmanager'), 0o755)
		}
		if os.is_executable(os.join_path(cmdl_root,'sdkmanager')) {
			return true
		}
		return error(@MOD+'.'+@FN+' '+'failed to install commandline tools in ${cmdl_root}')
	} else if opt.dep == .sdk {
		if opt.verbosity > 0 {
			println('Installing Latest SDK Platform Tools...')
		}
		cmd := [
			'yes |' // Windows
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"platform-tools"'
		]
		util.verbosity_print_cmd(cmd, opt.verbosity)
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			eprintln(cmd_res.output)
			return false
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
			eprintln(cmd_res.output)
			return false
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
			eprintln(cmd_res.output)
			return false
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
			eprintln(cmd_res.output)
			return false
		}
		return true
	}
	return error(@MOD+'.'+@FN+' '+'unknown install type ${opt.dep}')
}

fn download(opt InstallOptions) string {
	if opt.dep == .commandline_tools {
		uos := os.user_os().replace('windows','win').replace('macos','mac')
		url := 'https://dl.google.com/android/repository/commandlinetools-${uos}-6609375_latest.zip'
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

pub fn root_for(dep Dependency) string {
	mut root := ''
	if dep == .commandline_tools {
		root = os.join_path(sdk.tools_root(),'bin')
		mut check := os.join_path(root,'sdkmanager')
		if sdk.found() && os.is_executable(check) {
			return root
		}
		root = os.join_path(dependency_dir(dep),'tools','bin')
		check = os.join_path(root,'sdkmanager')
		if os.is_executable(check) {
			return root
		}
	}
	return root
}

fn dependency_dir(dep Dependency) string {
	mut root := ''
	if dep == .commandline_tools {
		root = os.join_path(util.cache_dir())
	}
	return root
}