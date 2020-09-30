module env

import os
import net.http

import android.sdk
import android.util

pub enum Dependency {
	commandline_tools
	sdk
	ndk
	build_tools
}

pub struct SetupOptions {
	dep			Dependency
	verbosity	int
}

pub fn setup(opt SetupOptions) ?bool {
	if opt.dep == .commandline_tools {
		cmdl_root := root_for(opt.dep)
		if cmdl_root != '' {
			return error(@MOD+'.'+@FN+' '+'commandline tools is already setup in ${cmdl_root}')
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
		return error(@MOD+'.'+@FN+' '+'failed to setup commandline tools in ${cmdl_root}')
	} else if opt.dep == .sdk {
		return error(@MOD+'.'+@FN+' '+'setup type ${opt.dep} is not implemented yet')
	} else if opt.dep == .ndk {
		return error(@MOD+'.'+@FN+' '+'setup type ${opt.dep} is not implemented yet')
	} else if opt.dep == .build_tools {
		if opt.verbosity > 0 {
			println('Installing "build-tools 24.0.3"...')
		}
		bt_cmd := [
			sdk.sdkmanager(),
			'--sdk_root="${sdk.root()}"',
			'"build-tools;24.0.3"'
		]
		util.verbosity_print_cmd(bt_cmd, opt.verbosity)
		bt_cmd_res := util.run(bt_cmd)
		if bt_cmd_res.exit_code > 0 {
			eprintln(bt_cmd_res.output)
			return true
		}
		return true
	}
	return error(@MOD+'.'+@FN+' '+'unknown setup type ${opt.dep}')
}

fn download(opt SetupOptions) string {
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