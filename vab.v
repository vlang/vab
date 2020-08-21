import os
import flag

import crypto.md5

import vxt
import semver

import java
import androidsdk as asdk
import androidndk as andk

const (
	exe = 'vab'
)

const (
	default_app_name = 'V Default App'
	default_package_id = 'org.v.android.default.app'
)

const (
	min_supported_api_level = '21'
)

// exe_dir return the absolute path of the directory, the executable resides in
fn exe_dir() string {
	return os.base_dir(os.real_path(os.executable()))
}

fn appendenv(name, value string) {
	os.setenv(name, os.getenv(name)+os.path_delimiter+value, true)
}

fn is_file(path string) bool {
	return !os.is_dir(path)
}

struct Options {
	app_name		string
	package_id	string

	verbosity		int

	work_dir		string

	device_id		string

	dump_env		bool

	list_apis		bool
	list_build_tools bool
mut:
	input			string
	output_file		string
	machine_friendly_app_name string

	build_tools		string
	api_level		string
	ndk_version		string

	assets_extra	[]string
}

fn main() {

	mut fp := flag.new_flag_parser(os.args)
	fp.application(exe)
	fp.version('0.1.0')
	fp.description('V Android Bootstrapper')
	//fp.arguments_description('[ARGS] <input>')

	fp.skip_executable()

	verbosity := fp.int_opt('verbosity', `v`, 'Verbosity level') or { 0 }

	mut opt := Options {

		assets_extra: fp.string_multi('assets', `a`, 'Asset dir(s) to include in build')

		device_id: fp.string('device-id', `i`, '', 'Deploy to this device ID after build')
		dump_env: fp.bool('dump', `d`, false, 'Dump the detected environment and exit')

		app_name: fp.string('name', 0, default_app_name, 'Pretty app name')
		package_id: fp.string('package-id', 0, default_package_id, 'App package ID (e.g. "org.v.app")')
		output_file: fp.string('output', `o`, '', 'Path to output file (dir or file)')

		verbosity: verbosity

		build_tools: fp.string('build-tools', 0, '', 'Version of build-tools to use')
		api_level: fp.string('api', 0, '', 'Android API level to use')

		ndk_version: fp.string('ndk-version', 0, '', 'Android NDK version to use')

		work_dir: os.join_path(os.temp_dir(), 'vab')

		list_apis:  fp.bool('list-api', 0, false, 'List available API levels')
		list_build_tools:  fp.bool('list-build-tools', 0, false, 'List available Build-tools versions')
	}

	fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		return
	}

	/*
	 * Validate environment
	 */
	os.setenv('JAVA_HOME','/usr/lib/jvm/java-8-openjdk-amd64',true) // For testing

	check_dependencies()

	resolve_options(mut opt)

	if opt.dump_env {
		dump_env(opt)
		exit(0)
	}

	if opt.list_apis {
		for api in asdk.apis_available() {
			println(api.all_after('android-'))
		}
		exit(0)
	}

	if opt.list_build_tools {
		for btv in asdk.build_tools_available() {
			println(btv)
		}
		exit(0)
	}

	if fp.args.len <= 0 {
		println(fp.usage())
		eprintln('$exe requires a valid input file or directory')
		exit(1)
	}

	mut input := fp.args[fp.args.len-1]
	if ! (os.is_dir(input) || os.file_ext(input) == '.v') {
		println(fp.usage())
		eprintln('$exe requires a valid V input file or directory')
		exit(1)
	}
	opt.input = input


	if ! compile(opt) {
		eprintln('Compiling didn\'t succeed')
		exit(1)
	}

	if ! package(opt) {
		eprintln('Packaging didn\'t succeed')
		exit(1)
	}

	if opt.device_id != '' {
		if ! deploy(opt) {
			eprintln('Deployment didn\'t succeed')
			exit(1)
		} else {
			if opt.verbosity > 0 {
				println('Deployed to ${opt.device_id} successfully')
			}
		}
	}
}

fn check_dependencies() {

	// Validate V install
	if vxt.vexe() == '' {
		eprintln('No V install could be detected')
		eprintln('Please provide a valid path to V via VEXE env variable')
		eprintln('or install V from https://github.com/vlang/v')
		exit(1)
	}

	// Validate Java requirements
	if ! java.jdk_found() {
		eprintln('No Java install(s) could be detected')
		eprintln('Please install Java 8 JDK')
		exit(1)
	}

	jdk_version := java.jdk_version()
	if jdk_version == '' {
		eprintln('No Java 8 JDK install could be detected')
		eprintln('Please install Java 8 JDK or provide a valid path via JAVA_HOME')
		exit(1)
	}

	jdk_semantic_version := semver.from(jdk_version) or { panic(err) }

	if ! jdk_semantic_version.satisfies('1.8.*') {
		// Some Android tools like `sdkmanager` currently only run with Java 8 JDK (1.8.x).
		// (Absolute mess, yes)
		eprintln('Java version ${jdk_version} is not supported')
		eprintln('Currently Java 8 JDK (1.8.x) is requried')
		exit(1)
	}

	// Validate Android SDK requirements
	if ! asdk.found() {
		eprintln('No Android SDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_SDK_ROOT')
		eprintln('or run `$exe install android-sdk`')
		exit(1)
	}

	// Validate Android NDK requirements
	if ! andk.found() {
		eprintln('No Android NDK could be detected.')
		eprintln('Please provide a valid path via ANDROID_NDK_ROOT')
		eprintln('or run `$exe install android-ndk`')
		exit(1)
	}
}

fn resolve_options(mut opt Options) {

	// Validate API level
	mut api_level := asdk.default_api_version()
	if opt.api_level != '' {
		if asdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			println('Android API level ${opt.api_level} is not available in SDK.')
			//println('(It can be installed with `$exe install android-api-${opt.api_level}`)')
			println('Falling back to default ${api_level}')
		}
	}
	if api_level == '' {
		eprintln('Android API level ${opt.api_level} is not available in SDK.')
		//eprintln('It can be installed with `$exe install android-api-${opt.api_level}`')
		exit(1)
	}
	if api_level.i16() < 20 {
		eprintln('Android API level ${api_level} is less than the recomended level (${min_supported_api_level}).')
		exit(1)
	}

	opt.api_level = api_level

	// Validate build-tools version
	mut build_tools_version := asdk.default_build_tools_version()
	if opt.build_tools != '' {
		if asdk.has_build_tools(opt.build_tools) {
			build_tools_version = opt.build_tools
		} else {
			// TODO FIX Warnings and add install function
			println('Android build-tools version ${opt.build_tools} is not available in SDK.')
			//println('(It can be installed with `$exe install android-build-tools-${opt.build_tools}`)')
			println('Falling back to default ${build_tools_version}')
		}
	}
	if build_tools_version == '' {
		eprintln('Android build-tools version ${opt.build_tools} is not available in SDK.')
		//eprintln('It can be installed with `$exe install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.build_tools = build_tools_version

	// Validate ndk version
	mut ndk_version := andk.default_version()
	if opt.ndk_version != '' {
		if andk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			println('Android NDK version ${opt.ndk_version} is not available.')
			//println('(It can be installed with `$exe install android-build-tools-${opt.build_tools}`)')
			println('Falling back to default ${ndk_version}')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version ${opt.ndk_version} is not available.')
		//eprintln('It can be installed with `$exe install android-api-${opt.api_level}`')
		exit(1)
	}

	opt.ndk_version = ndk_version

	// Output specific
	default_file_name := opt.app_name.replace(' ','_').to_lower()

	mut output_file := ''
	if opt.output_file != '' {
		output_file = opt.output_file.all_before(os.file_ext(opt.output_file))
	} else {
		output_file = default_file_name
	}
	output_file += '.apk'
	opt.output_file = output_file

	opt.machine_friendly_app_name = 'v' // TODO //opt.app_name.replace(' ','_').to_lower()
}

fn compile(opt Options) bool {

	os.mkdir_all(opt.work_dir)
	build_dir := os.join_path(opt.work_dir, 'build')

	vexe := vxt.vexe()
	v_output_file := os.join_path(opt.work_dir, 'v_android.c')
	v_cmd := [
		vexe,
		'-os android',
		'-apk',
		'-o "${v_output_file}"',
		opt.input
	]
	run_else_exit(opt,v_cmd)

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or { panic(err) }
		bytes << opt.str().bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 2 {
					println('Skipping compile. Hashes match ${hash}')
				}
				return true
			}
		}

	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash ${hash}')
		}
		os.rm(hash_file)
		mut hash_fh := open_file(hash_file, 'w+', 0o700) or { panic(err) }
		hash_fh.write(hash)
		hash_fh.close()
	}

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir)
	}
	os.mkdir(build_dir)

	v_home := vxt.home()
	//android_sdk_root := asdk.root()
	android_ndk_root := os.join_path(andk.root(),opt.ndk_version)

	/*
	* Compile sources for all Android archs
	*/

	archs := ['arm64-v8a','armeabi-v7a','x86','x86_64']

	// For all compilers
	mut cflags := []string{}
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}
	mut sources := []string{}


	// ... still a bit of a mess
	cflags << ['-Os','-fPIC','-fvisibility=hidden','-ffunction-sections','-fdata-sections','-ferror-limit=1']

	cflags << ['-Wall','-Wextra','-Wno-unused-variable','-Wno-unused-parameter','-Wno-unused-result','-Wno-unused-function','-Wno-missing-braces','-Wno-unused-label','-Werror=implicit-function-declaration']

	// TODO Here to make the compilers shut up :/
	cflags << ['-Wno-braced-scalar-init','-Wno-incompatible-pointer-types','-Wno-implicitly-unsigned-literal','-Wno-pointer-sign','-Wno-enum-conversion','-Wno-int-conversion','-Wno-int-to-pointer-cast','-Wno-sign-compare','-Wno-return-type']

	defines << ['-DAPPNAME="${opt.machine_friendly_app_name}"']
	defines << ['-DANDROID','-D__ANDROID__','-DANDROIDVERSION=${opt.api_level}']

	// TODO if full_screen
	defines << ['-DANDROID_FULLSCREEN']

	// NDK headers
	includes << ['-I"${andk.root()}/sysroot/usr/include"','-I"${andk.root()}/sysroot/usr/include/android"']

	// Sokol
	// TODO support both GLES2 & GLES3 - GLES2 should be default - trust me
	// TODO Toggle debug - probably follow v -prod flag somehow
	defines << ['-DSOKOL_DEBUG','-DSOKOL_GLES2']
	ldflags << ['-uANativeActivity_onCreate','-usokol_main']
	includes << ['-I"${v_home}/thirdparty/sokol"','-I"${v_home}/thirdparty/sokol/util"']

	// stb_image
	includes << ['-I"${v_home}/thirdparty/stb_image"']
	sources << ['"${v_home}/thirdparty/stb_image/stbi.c"']

	// fontstash
	includes << ['-I"${v_home}/thirdparty/fontstash"']

	// misc
	ldflags << ['-llog','-landroid','-lEGL','-lGLESv2','-lm']

	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp','-m32']
	mut cflags_x86 := ['-march=i686','-mtune=intel','-mssse3','-mfpmath=sse','-m32']
	mut cflags_x86_64 := ['-march=x86-64','-msse4.2','-mpopcnt','-m64','-mtune=intel']

	mut host_arch := ''
	uos := os.user_os()
	if uos == 'windows' { host_arch = 'windows-x86_64' }
	if uos == 'macos'   { host_arch = 'darwin-x86_64' }
	if uos == 'linux'   { host_arch = 'linux-x86_64' }


	mut arch_alt := map[string]string
	arch_alt['arm64-v8a'] = 'aarch64'
	arch_alt['armeabi-v7a'] = 'armv7a'
	arch_alt['x86'] = 'x86_64'
	arch_alt['x86_64'] = 'x86_64'

	mut arch_cc := map[string]string
	mut arch_libs := map[string]string


	// TODO do Windows and macOS as well
	for arch in archs {
		mut eabi := ''
		if arch == 'armeabi-v7a' { eabi = 'eabi' }

		arch_cc[arch] = os.join_path(android_ndk_root,'toolchains','llvm','prebuilt',host_arch,'bin',arch_alt[arch]+'-linux-android${eabi}${opt.api_level}-clang')
		arch_libs[arch] = os.join_path(android_ndk_root,'toolchains','llvm','prebuilt',host_arch,'sysroot','usr','lib',arch_alt[arch]+'-linux-android'+eabi,opt.api_level)
	}

	mut arch_cflags := map[string][]string
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	// Cross compile .so lib files
	for arch in archs {

		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir)

		build_cmd := [ arch_cc[arch],
			cflags.join(' '),
			includes.join(' '),
			defines.join(' '),
			sources.join(' '),
			arch_cflags[arch].join(' '),
			'-o "${arch_lib_dir}/lib${opt.machine_friendly_app_name}.so"',
			v_output_file,
			'-L"'+arch_libs[arch]+'"',
			ldflags.join(' ')
		]
		comp_res := run_else_exit(opt,build_cmd)

		if opt.verbosity > 1 {
			println(comp_res)
		}
	}

	// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
	armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
	os.mkdir_all(armeabi_lib_dir)

	armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a','lib${opt.machine_friendly_app_name}.so')
	armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.machine_friendly_app_name}.so')
	os.cp( armeabi_lib_src, armeabi_lib_dst) or { panic(err) }

	return true
}

fn package(opt Options) bool {

	// Build APK
	if opt.verbosity > 0 {
		println('Preparing package')
	}

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(asdk.build_tools_root(),opt.build_tools)

	javac := os.join_path(java.jdk_root(),'bin','javac')
	keytool := os.join_path(java.jdk_root(),'bin','keytool')
	aapt := os.join_path(build_tools_path,'aapt')
	dx := os.join_path(build_tools_path,'dx')
	zipalign := os.join_path(build_tools_path,'zipalign')
	apksigner := os.join_path(build_tools_path,'apksigner')


	//work_dir := opt.work_dir
	//VAPK_OUT=${VAPK}/..

	package_path := os.join_path(opt.work_dir, 'package')
	os.mkdir_all(package_path)

	android_extras_path := os.join_path(exe_dir(), 'platforms', 'android')

	cp_all(android_extras_path, package_path, false)


	if opt.verbosity > 0 {
		println('Copying assets')
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
	if is_file(opt.input) {
		assets_by_side_path = os.dir(opt.input)
	}

	// Look for "assets" dir in same location as input
	assets_by_side := os.join_path(assets_by_side_path,'assets')
	if os.is_dir(assets_by_side) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_by_side}')
		}
		cp_all(assets_by_side, assets_path, false)
	}

	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_in_dir}')
		}
		cp_all(assets_in_dir, assets_path, false)
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

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file),'')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.apk')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.apk')
	tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product)
	os.rm(tmp_unsigned_product)
	os.rm(tmp_unaligned_product)

	android_runtime := os.join_path(asdk.platforms_root(),'android-'+opt.api_level,'android.jar')

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
	run_else_exit(opt,aapt_cmd)

	pwd := os.getwd()
	os.chdir(package_path)

	// Compile java sources
	java_sources := walk_ext(os.join_path(package_path,'src'), '.java')

	mut javac_cmd_part := [
		javac,
		'-d obj', //+obj_path,
		'-source 1.7',
		'-target 1.7',
		'-sourcepath src',
		'-bootclasspath '+android_runtime
	]
	javac_cmd_part << java_sources

	run_else_exit(opt,javac_cmd_part)

	// Dex
	dx_cmd := [
		dx,
		'--verbose',
		'--dex',
		'--output='+os.join_path('bin','classes.dex'),
		'obj', //obj_path
	]
	run_else_exit(opt,dx_cmd)

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
	run_else_exit(opt,aapt_cmd)


	os.chdir(build_path)

	collect_libs := walk_ext(os.join_path(build_path,'lib'), '.so')

	for lib in collect_libs {
		lib_s := lib.replace(build_path+os.path_separator, '')
		aapt_cmd = [
			aapt,
			'add',
			'-v',
			tmp_unaligned_product,
			lib_s
		]
		run_else_exit(opt,aapt_cmd)
	}

	os.chdir(pwd)


	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		tmp_unaligned_product,
		tmp_unsigned_product
	]
	run_else_exit(opt,zipalign_cmd)

	// Sign the APK
	keystore_file := os.join_path(exe_dir(),'debug.keystore')
	keystore_password := 'android'

	if ! os.exists(keystore_file) {
		if opt.verbosity > 0 {
			println('Generating debug.keystore')
		}
		keytool_cmd := [
			keytool,
			'-genkeypair',
			'-keystore '+keystore_file,
			'-storepass android',
			'-alias androiddebugkey',
			'-keypass '+keystore_password,
			'-keyalg RSA',
			'-validity 10000',
			'-dname \'CN=,OU=,O=,L=,S=,C=\''
		]
		run_else_exit(opt,keytool_cmd)
	}

	mut apksigner_cmd := [
		apksigner,
		'sign',
		'--ks "'+keystore_file+'"',
		'--ks-pass pass:'+keystore_password,
		'--key-pass pass:'+keystore_password,
		'--ks-key-alias "androiddebugkey"',
		'--out '+tmp_product,
		tmp_unsigned_product
	]
	run_else_exit(opt,apksigner_cmd)

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		tmp_product,
	]
	run_else_exit(opt,apksigner_cmd)


	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	if opt.verbosity > 0 {
		println('Generated package ${os.real_path(opt.output_file)}')
	}

	return true
}

fn deploy(opt Options) bool {

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
			opt.output_file
		]
		run_else_exit(opt,adb_cmd)

		os.system('killall adb')
		//os.system('Taskkill /IM adb.exe /F)
		return true
	}
	return false
}

fn run_else_exit(opt Options, args []string) string {
	cmd := args.join(' ')
	if opt.verbosity > 1 {
		println('Running ${args[0]}')
		if opt.verbosity > 2 {
			println(cmd)
		}
	}
	res := os.exec(cmd) or { os.Result{1,''} }
	if res.exit_code > 0 {
		eprintln('${args[0]} failed with exit code ${res.exit_code}')
		eprintln(res.output)
		exit(1)
	}
	return res.output
}

fn dump_env(opt Options) {
	println('V')
	println('\tVersion ${vxt.version()}')
	println('\tPath ${vxt.home()}')
	println('Java')
	println('\tJDK')
	println('\t\tVersion ${java.jdk_version()}')
	println('\t\tPath ${java.jdk_root()}')
	println('Android')
	println('\tSDK')
	println('\t\tPath ${asdk.root()}')
	println('\tNDK')
	println('\t\tVersion ${opt.ndk_version}')
	println('\t\tPath ${andk.root()}')
	println('\tBuild')
	println('\t\tAPI ${opt.api_level}')
	println('\t\tBuild-tools ${opt.build_tools}')
	println('Product')
	println('\tName "${opt.app_name}"')
	println('\tPackage ${opt.package_id}')
	println('\tOutput ${opt.output_file}')
	println('')
}