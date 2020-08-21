module androidsdk

import os

const (
	home = os.home_dir()
)

// Possible default locations of the SDK
// https://stackoverflow.com/a/47630714/1904615
const (
	possible_sdk_paths_windows = [
		os.join_path(os.getenv('LOCALAPPDATA'), 'Local\\Android\\sdk')
		os.join_path(home, 'AppData\\Local\\Android\\sdk')
	]
	possible_sdk_paths_macos = [
		os.join_path(home, 'Library/Android/sdk')
	]
	possible_sdk_paths_linux = [
		os.join_path(home, "Android/Sdk")
	]
)

// root will try to detect where the Android SDK is installed. Otherwise return blank
pub fn root() string {
	mut sdk_root := os.getenv('ANDROID_SDK_ROOT')

	if sdk_root == '' {
		sdk_root = os.getenv('ANDROID_HOME')
	}

	// Detect OS type at runtime - in case we're in some exotic environment
	uos := os.user_os()

	if sdk_root == '' {
		mut dirs := []string{}

		if uos == 'windows' { dirs = possible_sdk_paths_windows }
		if uos == 'macos'   { dirs = possible_sdk_paths_macos }
		if uos == 'linux'   { dirs = possible_sdk_paths_linux }

		for dir in dirs {
			if os.exists(dir) && os.is_dir(dir) { return dir }
		}
	}
	// Last resort - try and detect by getting path to 'adb'
	if sdk_root == '' {
		mut adb_path := ''

		if os.exists_in_system_path('adb') {
			adb_path = os.find_abs_path_of_executable('adb') or { return '' }
			if adb_path != '' {
				// adb normally reside in 'path/to/sdk_root/platform-tools/'
				sdk_root = os.real_path(os.join_path(os.dir(adb_path),'..'))
			}
		}
	}
	return sdk_root
}

pub fn found() bool {
	return root() != ''
}

pub fn build_tools_root() string {
	return os.join_path(root(),'build-tools')
}

pub fn platform_tools_root() string {
	return os.join_path(root(),'platform-tools')
}

pub fn platforms_root() string {
	return os.join_path(root(),'platforms')
}

pub fn platforms_dir() []string {
	return find_sorted(platforms_root())
}

pub fn apis_available() []string {
	return ls_sorted(platforms_root())
}

pub fn has_api(api string) bool {
	return 'android-'+api in apis_available()
}

pub fn has_build_tools(version string) bool {
	return version in build_tools_available()
}

pub fn build_tools_available() []string {
	return ls_sorted(build_tools_root())
}

pub fn default_build_tools_version() string {
	return os.file_name(default_build_tools_dir())
}

pub fn default_api_version() string {
	return os.file_name(default_platforms_dir()).all_after('android-')
}

pub fn default_build_tools_dir() string {
	dirs := find_sorted(build_tools_root())
	if dirs.len > 0 {
		return dirs.first()
	}
	return ''
}

pub fn default_platforms_dir() string {
	dirs := find_sorted(platforms_root())
	if dirs.len > 0 {
		return dirs.first()
	}
	return ''
}

/*
 * Utility functions
 */
fn find_sorted(path string) []string {
	mut dirs := []string{}
	mut files := os.ls(path) or { return dirs }
	for file in files {
		if os.is_dir(os.real_path(os.join_path(path,file))) {
			dirs << os.real_path(os.join_path(path,file))
		}
	}
	dirs.sort()
	dirs.reverse_in_place()
	return dirs
}

fn ls_sorted(path string) []string {
	mut dirs := []string{}
	mut files := os.ls(path) or { return dirs }
	for file in files {
		if os.is_dir(os.real_path(os.join_path(path,file))) {
			dirs << file
		}
	}
	dirs.sort()
	dirs.reverse_in_place()
	return dirs
}
/*
fn which(exe string) string {
	mut which_exe := 'which'
		if uos == 'windows' {
			which_exe = 'where'
		}
		res := os.exec(which_exe+' '+exe) or { os.Result{1,''} }
		if res.exit_code > 0 { return '' }
		return res.output
}
*/