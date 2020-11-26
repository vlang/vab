// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import regex

import java

import android.sdk
import android.util

const (
	default_app_name = 'V Test App'
	default_package_id = 'org.v.android.test.app'
)

pub struct PackageOptions {
	verbosity		int
	work_dir		string

	api_level		string
	build_tools		string

	app_name		string
	lib_name		string
	package_id		string
	icon			string
	version_code	int

	v_flags			[]string

	input			string
	assets_extra	[]string
	output_file		string

	keystore		string
	keystore_alias	string

	keystore_password string
	keystore_alias_password	string

	base_files		string
}

pub fn package(opt PackageOptions) bool {

	// Build APK
	if opt.verbosity > 0 {
		println('Preparing package')
	}

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(sdk.build_tools_root(),opt.build_tools)

	javac := os.join_path(java.jdk_bin_path(),'javac')
	keytool := os.join_path(java.jdk_bin_path(),'keytool')
	aapt := os.join_path(build_tools_path,'aapt')
	dx := os.join_path(build_tools_path,'dx')
	zipalign := os.join_path(build_tools_path,'zipalign')
	apksigner := os.join_path(build_tools_path,'apksigner')

	//work_dir := opt.work_dir
	//VAPK_OUT=${VAPK}/..

	// Prepare and modify package skeleton shipped with vab
	// Copy assets etc.
	package_path, assets_path := prepare_base(opt)

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file),'')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.apk')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.apk')
	tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product)
	os.rm(tmp_unsigned_product)
	os.rm(tmp_unaligned_product)

	android_runtime := os.join_path(sdk.platforms_root(),'android-'+opt.api_level,'android.jar')

	src_path := os.join_path(package_path,'src')
	res_path := os.join_path(package_path,'res')

	obj_path := os.join_path(package_path, 'obj')
	os.mkdir_all(obj_path)
	bin_path := os.join_path(package_path, 'bin')
	os.mkdir_all(bin_path)

	mut aapt_cmd := [
		aapt,
		'package',
		'-v',
		'-f',
		'-m',
		'-M '+os.join_path(package_path,'AndroidManifest.xml'),
		'-S '+res_path,
		'-J '+src_path,
		'-A '+assets_path,
		'-I '+android_runtime
		//'--target-sdk-version ${ANDROIDTARGET}'
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)

	pwd := os.getwd()
	os.chdir(package_path)

	// Compile java sources
	java_sources := os.walk_ext(os.join_path(package_path,'src'), '.java')

	mut javac_cmd := [
		javac,
		'-d obj', //+obj_path,
		'-source 1.7',
		'-target 1.7',
		'-sourcepath src',
		'-bootclasspath '+android_runtime
	]
	javac_cmd << java_sources

	util.verbosity_print_cmd(javac_cmd, opt.verbosity)
	util.run_or_exit(javac_cmd)

	// Dex
	dx_cmd := [
		dx,
		'--verbose',
		'--dex',
		'--output='+os.join_path('bin','classes.dex'),
		'obj', //obj_path
	]
	util.verbosity_print_cmd(dx_cmd, opt.verbosity)
	util.run_or_exit(dx_cmd)

	// Second run
	aapt_cmd = [
		aapt,
		'package',
		'-v',
		'-f',
		'-S '+res_path,
		'-M '+os.join_path(package_path,'AndroidManifest.xml'),
		'-A '+assets_path,
		'-I '+android_runtime,
		'-F '+tmp_unaligned_product,
		'bin' //bin_path
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)


	os.chdir(build_path)

	collect_libs := os.walk_ext(os.join_path(build_path,'lib'), '.so')

	for lib in collect_libs {
		lib_s := lib.replace(build_path+os.path_separator, '')
		aapt_cmd = [
			aapt,
			'add',
			'-v',
			tmp_unaligned_product,
			lib_s
		]
		util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
		util.run_or_exit(aapt_cmd)
	}

	os.chdir(pwd)


	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		tmp_unaligned_product,
		tmp_unsigned_product
	]
	util.verbosity_print_cmd(zipalign_cmd, opt.verbosity)
	util.run_or_exit(zipalign_cmd)

	// Sign the APK
	keystore_file := opt.keystore
	if !os.is_file(keystore_file) {
		if opt.verbosity > 0 {
			println('Generating debug.keystore')
		}
		keytool_cmd := [
			keytool,
			'-genkeypair',
			'-keystore '+keystore_file,
			'-storepass android',
			'-alias androiddebugkey',
			'-keypass android',
			'-keyalg RSA',
			'-validity 10000',
			'-dname \'CN=,OU=,O=,L=,S=,C=\''
		]
		util.verbosity_print_cmd(keytool_cmd, opt.verbosity)
		util.run_or_exit(keytool_cmd)
	}

	// Defaults from Android debug key
	mut keystore_alias := 'androiddebugkey'
	mut keystore_password := 'android'
	mut keystore_alias_password := keystore_password

	if opt.keystore_alias != '' {
		keystore_alias = opt.keystore_alias
	}
	if opt.keystore_password != '' {
		keystore_password = opt.keystore_password
	}
	if opt.keystore_alias_password != '' {
		keystore_alias_password = opt.keystore_alias_password
	}

	mut apksigner_cmd := [
		apksigner,
		'sign',
		'--ks "'+keystore_file+'"',
		'--ks-pass pass:'+keystore_password,
		'--key-pass pass:'+keystore_alias_password,
		'--ks-key-alias "'+keystore_alias+'"',
		'--out '+tmp_product,
		tmp_unsigned_product
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_exit(apksigner_cmd)

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		tmp_product,
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_exit(apksigner_cmd)

	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	return true
}

fn prepare_base(opt PackageOptions) (string,string) {

	package_path := os.join_path(opt.work_dir, 'package')
	if os.exists(package_path) {
		if opt.verbosity > 0 {
			println('Removing previous package directory')
		}
		os.rmdir_all(package_path)
	}
	os.mkdir_all(package_path)

	base_files_path := opt.base_files
	if opt.verbosity > 0 {
		println('Copying base files')
		if opt.verbosity > 2 {
			os.walk(base_files_path, fn(entry string) {
				println(entry)
			})
		}
	}
	os.cp_all(base_files_path, package_path, true)

	if opt.verbosity > 0 {
		println('Modifying base files')
	}

	// TODO Validate that Java doesn't allow the word "default" in package IDs???

	if '-prod' in opt.v_flags && opt.package_id == default_package_id {
		eprintln('Warning: using default package ID "${default_package_id}". Please do not deploy to app stores using this ID')
	}
	package_id_path := opt.package_id.split('.').join(os.path_separator)
	os.mkdir_all(os.join_path(package_path, 'src', package_id_path))

	native_activity_path := os.join_path(package_path, 'src', 'org', 'v', 'android')
	native_activity_file := os.join_path(native_activity_path, 'Native.java')
	if os.is_file(native_activity_file) {
		mut java_src := os.read_file(native_activity_file) or { panic(err) }

		mut re := regex.regex_opt(r'.*package\s+(org.v.android).*') or { panic(err) }
		mut start, _ := re.match_string(java_src)
		// Set new package ID if found
		if start >= 0 && re.groups.len > 0 {
			java_src = java_src[0..re.groups[0]] + opt.package_id + java_src[re.groups[1]..java_src.len]
		}
		// Set lib_name
		re = regex.regex_opt(r'.*loadLibrary.*"(.*)".*') or { panic(err) }
		start, _ = re.match_string(java_src)
		// Set new package ID if found
		if start >= 0 && re.groups.len > 0 {
			java_src = java_src[0..re.groups[0]] + opt.lib_name + java_src[re.groups[1]..java_src.len]
		}
		os.write_file(os.join_path(package_path, 'src', package_id_path, 'Native.java'), java_src)
		// TODO this can be done better and smarter - but works for now
		os.rm(native_activity_file)
		if os.is_dir_empty(os.join_path(package_path, 'src', 'org', 'v', 'android')) {
			os.rmdir_all(os.join_path(package_path, 'src', 'org', 'v', 'android'))
		}
		if os.is_dir_empty(os.join_path(package_path, 'src', 'org', 'v')) {
			os.rmdir_all(os.join_path(package_path, 'src', 'org', 'v'))
		}
		if os.is_dir_empty(os.join_path(package_path, 'src', 'org')) {
			os.rmdir_all(os.join_path(package_path, 'src', 'org'))
		}
	}

	// Replace in AndroidManifest.xml
	manifest_path := os.join_path(package_path, 'AndroidManifest.xml')
	if os.is_file(manifest_path) {
		mut manifest := os.read_file(manifest_path) or { panic(err) }
		mut re := regex.regex_opt(r'.*<manifest\s.*\spackage\s*=\s*"(.+)".*>') or { panic(err) }
		mut start, _ := re.match_string(manifest)
		// Set package ID if found
		if start >= 0 && re.groups.len > 0 {
			manifest = manifest[0..re.groups[0]] + opt.package_id + manifest[re.groups[1]..manifest.len]
		}

		re = regex.regex_opt(r'.*<manifest\s.*\sandroid:versionCode\s*=\s*"(.+)".*>') or { panic(err) }
		start, _ = re.match_string(manifest)
		if start >= 0 && re.groups.len > 0 {
			manifest = manifest[0..re.groups[0]] + opt.version_code.str() + manifest[re.groups[1]..manifest.len]
		}

		is_debug_build := ('-cg' in opt.v_flags)
		re = regex.regex_opt(r'.*<application\s.*\s+android:debuggable\s*=\s*"(.*)".*>') or { panic(err) }
		start, _ = re.match_string(manifest)
		// Set debuggable attribute if found
		if start >= 0 && re.groups.len > 0 {
			manifest = manifest[0..re.groups[0]] + is_debug_build.str() + manifest[re.groups[1]..manifest.len]
		}

		re = regex.regex_opt(r'.*\s+android:minSdkVersion\s*=\s*"(.*)".*') or { panic(err) }
		start, _ = re.match_string(manifest)
		// When building with Android native it's recommended (even quite necessary) that minSdkVersion is equal to compiled sdk version :(
		// Otherwise you have all kinds of cryptic errors when the app is started.
		// Google Play, at the time of writing, requires to build against level 29 as a minimum (App will be rejected otherwise).
		if start >= 0 && re.groups.len > 0 {
			manifest = manifest[0..re.groups[0]] + opt.api_level + manifest[re.groups[1]..manifest.len]
		}
		os.write_file(manifest_path, manifest)
	}

	// Replace in res/values/strings.xml
	strings_path := os.join_path(package_path, 'res', 'values', 'strings.xml')
	if os.is_file(strings_path) {
		mut content := os.read_file(strings_path) or { panic(err) }
		mut re := regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"app_name"\s*>(.*)</string.*') or { panic(err) }
		mut start, _ := re.match_string(content)
		// Set app name if found
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.app_name + content[re.groups[1]..content.len]
		}
		// Set lib name if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"lib_name"\s*>(.*)</string.*') or { panic(err) }
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.lib_name + content[re.groups[1]..content.len]
		}
		// Set package ID if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"package_name"\s*>(.*)</string.*') or { panic(err) }
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.package_id + content[re.groups[1]..content.len]
		}
		//println(content)
		//println(strings_path)
		os.write_file(strings_path, content)
	}

	if opt.verbosity > 0 {
		println('Copying assets')
	}

	if os.is_file(opt.icon) && os.file_ext(opt.icon) == '.png' {
		icon_path := os.join_path(package_path, 'res', 'mipmap', 'icon.png')
		if opt.verbosity > 0 {
			println('Copying icon')
		}
		os.rm(icon_path)
		os.cp(opt.icon,icon_path)
	}

	assets_path := os.join_path(package_path, 'assets')
	os.mkdir_all(assets_path)

	/*
	test_asset := os.join_path(assets_path, 'test.txt')
	os.rm(test_asset)
	mut fh := open_file(test_asset, 'w+', 0o755) or { panic(err) }
	fh.write('test')
	fh.close()*/

	mut assets_by_side_path := opt.input
	if ! os.is_dir(opt.input) {
		assets_by_side_path = os.dir(opt.input)
	}

	// Look for "assets" dir in same location as input
	assets_by_side := os.join_path(assets_by_side_path,'assets')
	if os.is_dir(assets_by_side) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_by_side}')
		}
		os.cp_all(assets_by_side, assets_path, false)
	}

	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_in_dir}')
		}
		os.cp_all(assets_in_dir, assets_path, false)
	}

	// Look in user provided dir
	for user_asset in opt.assets_extra {
		if os.is_dir(user_asset) {
			if opt.verbosity > 0 {
				println('Including assets from ${user_asset}')
			}
			os.cp_all(user_asset, assets_path, false)
		} else {
			os.cp(user_asset, assets_path) or {
				eprintln('Skipping invalid asset file ${user_asset}')
			}
		}
	}
	return package_path, assets_path
}
