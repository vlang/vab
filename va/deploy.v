module va

import os

import androidsdk as asdk

pub struct DeployOptions {
	verbosity	int
	device_id	string
	deploy_file string
}

pub fn deploy(opt DeployOptions) bool {

	// Deploy
	if opt.device_id != '' {
		if opt.verbosity > 0 {
			println('Deploying to ${opt.device_id}')
		}

		adb := os.join_path(asdk.platform_tools_root(),'adb')

		adb_cmd := [
			adb,
			'-s "${opt.device_id}"',
			'install',
			'-r',
			opt.deploy_file
		]
		verbosity_print_cmd(adb_cmd, opt.verbosity)
		run_else_exit(adb_cmd)

		os.system('killall adb')
		//os.system('Taskkill /IM adb.exe /F)
		return true
	}
	return false
}
