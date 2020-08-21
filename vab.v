import os
import flag

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
	default_package_name = 'org.v.android.default.app'
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

struct Options {
	app_name		string
	package_name	string
	output_file		string

	build_tools		string
	api_level		string
	ndk_version		string
}

fn main() {

	mut fp := flag.new_flag_parser(os.args)
	fp.application(exe)
	fp.version('0.1.0')
	fp.description('V Android Bootstrapper')
	//fp.arguments_description('[ARGS] <input>')

	fp.skip_executable()

	opt := Options {
		app_name: fp.string('name', 0, default_app_name, 'Application name')
		package_name: fp.string('package', 0, default_package_name, 'Application package name')
		output_file: fp.string('output', `o`, '', 'Output file')

		build_tools: fp.string('build-tools', 0, '', 'build-tools version')
		api_level: fp.string('api', 0, '', 'Android API level')

		ndk_version: fp.string('ndk-version', 0, '', 'NDK version')
	}

	default_file_name := opt.app_name.replace(' ','_').to_lower()

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

	vexe := vxt.vexe()

	/*
	 * Validate input
	 */

	// Validate API level
	mut api_level := asdk.default_api_version()
	if opt.api_level != '' {
		if asdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			println('Android API level ${opt.api_level} is not available in SDK.')
			println('(It can be installed with `$exe install android-api-${opt.api_level}`)')
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

	// Validate build-tools version
	mut build_tools_version := asdk.default_build_tools_version()
	if opt.build_tools != '' {
		if asdk.has_build_tools(opt.build_tools) {
			build_tools_version = opt.build_tools
		} else {
			// TODO FIX Warnings and make
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

	// Validate ndk version
	mut ndk_version := andk.default_version()
	if opt.ndk_version != '' {
		if andk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and make
			println('Android NDK version ${opt.ndk_version} is not available.')
			//println('(It can be installed with `$exe install android-build-tools-${opt.build_tools_version}`)')
			println('Falling back to default ${ndk_version}')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version ${opt.ndk_version} is not available.')
		//eprintln('It can be installed with `$exe install android-api-${opt.api_level}`')
		exit(1)
	}

	// Output specific
	mut app_name := opt.app_name
	mut package_name := opt.package_name

	mut output_file := ''
	if opt.output_file != '' {
		output_file = opt.output_file.all_before(os.file_ext(opt.output_file))
	} else {
		output_file = default_file_name
	}
	output_file += '.apk'

	machine_friendly_app_name := app_name.replace(' ','_').to_lower()


	$if debug {
		// Summary
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
		println('\t\tVersion ${ndk_version}')
		println('\t\tPath ${andk.root()}')
		println('\tBuild')
		println('\t\tAPI ${api_level}')
		println('\t\tBuild-tools ${build_tools_version}')
		println('Product')
		println('\tName "${app_name}"')
		println('\tPackage ${package_name}')
		println('\tOutput ${output_file}')
		println('')
	}

	mut input := ''
	if fp.args.len > 0 {
		input = fp.args[fp.args.len-1]
	}

	if fp.args.len <= 0 {
		println(fp.usage())
		eprintln('$exe requires a valid input file or directory')
		exit(1)
	}

	if ! (os.is_dir(input) || os.file_ext(input) == '.v') {
		println(fp.usage())
		eprintln('$exe requires a valid input file or directory')
		exit(1)
	}

	work_dir := os.join_path(os.temp_dir(), 'vab')
	// Remove any previous builds
	if os.is_dir(work_dir) {
		os.rmdir_all(work_dir)
	}

	v_comp_out_file := os.join_path(work_dir, 'v_android.c')
	os.mkdir_all(work_dir)

	build_dir := os.join_path(work_dir, 'apk')
	os.mkdir(build_dir)

	v_comp_res := os.exec('$vexe -os android -apk -o "$v_comp_out_file" "$input"') or { os.Result{1,''} }
	if v_comp_res.exit_code > 0 {
		eprintln('v compile failed with exit code ${v_comp_res.exit_code}')
		eprintln(v_comp_res.output)
		exit(1)
	}

	v_home := vxt.home()
	//android_sdk_root := asdk.root()
	android_ndk_root := os.join_path(andk.root(),ndk_version)

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

	defines << ['-DAPPNAME="${machine_friendly_app_name}"']
	defines << ['-DANDROID','-D__ANDROID__','-DANDROIDVERSION=${api_level}']

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

		arch_cc[arch] = os.join_path(android_ndk_root,'toolchains','llvm','prebuilt',host_arch,'bin',arch_alt[arch]+'-linux-android${eabi}${api_level}-clang')
		arch_libs[arch] = os.join_path(android_ndk_root,'toolchains','llvm','prebuilt',host_arch,'sysroot','usr','lib',arch_alt[arch]+'-linux-android'+eabi,api_level)
	}

	mut arch_cflags := map[string][]string
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	// Cross compile .so lib files
	for arch in archs {
		println('Building $arch')

		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir)

		build_cmd := [ arch_cc[arch],
			cflags.join(' '),
			includes.join(' '),
			defines.join(' '),
			sources.join(' '),
			arch_cflags[arch].join(' '),
			'-o "${arch_lib_dir}/lib${machine_friendly_app_name}.so"',
			v_comp_out_file,
			'-L"'+arch_libs[arch]+'"',
			ldflags.join(' ')
		].join(' ')

		//println(build_cmd)
		arch_comp_res := os.exec(build_cmd) or { panic(err) }
		if arch_comp_res.exit_code > 0 {
			eprintln('$arch compile failed with exit code ${arch_comp_res.exit_code}')
			eprintln(arch_comp_res.output)
			exit(1)
		}
	}

	// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
	armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
	os.mkdir_all(armeabi_lib_dir)

	armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a','lib${machine_friendly_app_name}.so')
	armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${machine_friendly_app_name}.so')
	os.cp( armeabi_lib_src, armeabi_lib_dst) or { panic(err) }


/*  TODO
	// Build APK

	ADB="${PLATFORM_TOOLS}/adb"
	AAPT="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/aapt"
	ZIPALIGN="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/zipalign"
	APKSIGNER="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/apksigner"
	KEYTOOL="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/keytool"
	DX="${BUILD_TOOLS}/${BUILD_TOOLS_VERSION}/dx"

	VAPK_OUT=${VAPK}/..

	cp -r $SCRIPT_DIR/android/ * ${VAPK}/

	mkdir -p ${VAPK}/assets
	echo "V test asset file" > ${VAPK}/assets/asset.txt

	[ -d "${SCRIPT_DIR}/assets" ] && echo "  - Copying assets" && cp -a "${SCRIPT_DIR}/assets" ${VAPK}/assets/ && ls ${VAPK}/assets/

	[ -d "${VSRC}/assets" ] && echo "  - Copying assets" && cp -a "${VSRC}assets/" ${VAPK} && ls ${VAPK}/assets/

	rm -rf ${VAPK_OUT}/temp.apk
	rm -rf ${VAPK_OUT}/vapk.unsigned.apk
	rm -rf ${VAPK_OUT}/vapk.apk

	rm -rf ${VAPK_OUT}/vapkrp

	${AAPT} package -v -f -m \
		-S ${VAPK}/res \
		-J ${VAPK}/src \
		-M ${VAPK}/AndroidManifest.xml \
		-I ${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar \
		-A ${VAPK}/assets

	#--target-sdk-version ${ANDROIDTARGET}

	_BACK="$(pwd)"
	cd "${VAPK}"

	#RT_JAR="$JAVA_HOME/jre/lib/rt.jar"
	RT_JAR=${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar

	mkdir -p ${VAPK}/obj
	mkdir -p ${VAPK}/bin

	javac -d ./obj \
		-source 1.7 \
		-target 1.7 \
		-sourcepath src \
		-bootclasspath "$RT_JAR" \
		${VAPK}/src/org/v/vtest/R.java \
		${VAPK}/src/org/v/vtest/Native.java

	${DX} --verbose --dex --output=bin/classes.dex ./obj

	${AAPT} package -v -f \
		-S res \
		-M AndroidManifest.xml \
		-A assets \
		-I ${ANDROID_SDK_ROOT}/platforms/android-${ANDROIDVERSION}/android.jar \
		-F ${VAPK_OUT}/temp.apk \
		bin


	cd "$_BACK"


	_BACK="$(pwd)"
	cd "${VAPK}"

	test -e lib/arm64-v8a/lib${APPNAME}.so   && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/arm64-v8a/lib${APPNAME}.so
	test -e lib/armeabi/lib${APPNAME}.so     && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/armeabi/lib${APPNAME}.so
	test -e lib/armeabi-v7a/lib${APPNAME}.so && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/armeabi-v7a/lib${APPNAME}.so
	test -e lib/x86/lib${APPNAME}.so         && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/x86/lib${APPNAME}.so
	test -e lib/x86_64/lib${APPNAME}.so      && ${AAPT} add -v ${VAPK_OUT}/temp.apk lib/x86_64/lib${APPNAME}.so
	cd "$_BACK"

	# -p ?
	${ZIPALIGN} -v -f 4 ${VAPK_OUT}/temp.apk ${VAPK_OUT}/vapk.unsigned.apk


	// Sign the APK
	KEYSTORE_FILE="$SCRIPT_DIR/debug.keystore"
	KEYSTORE_PASSWORD="android"

	test -e $KEYSTORE_FILE || keytool -genkeypair -keystore $KEYSTORE_FILE -storepass android -alias androiddebugkey -keypass $KEYSTORE_PASSWORD -keyalg RSA -validity 10000 -dname 'CN=,OU=,O=,L=,S=,C='

	${APKSIGNER} sign --ks "$KEYSTORE_FILE" --ks-pass pass:$KEYSTORE_PASSWORD --key-pass pass:$KEYSTORE_PASSWORD --ks-key-alias "androiddebugkey" --out ${VAPK_OUT}/vapk.apk ${VAPK_OUT}/vapk.unsigned.apk

	#${APKSIGNER} sign --ks "$KEYSTORE_FILE" --ks-pass stdin --key-pass stdin --out ${VAPK_OUT}/vapk.apk ${VAPK_OUT}/vapk.unsigned.apk

	${APKSIGNER} verify -v ${VAPK_OUT}/vapk.apk


	// Deploy
	if [ -z ${ANDROID_SERIAL+x} ]; then
		#ANDROID_SERIAL=emulator-5554
		#ANDROID_SERIAL=4df144551637af2d # S3
		ANDROID_SERIAL=a4599aaf # S5
		#ANDROID_SERIAL=R58M61681DP # A40
	fi

	echo "Deploying to device $ANDROID_SERIAL"
	echo "adb -s \"$ANDROID_SERIAL\" install -r ${VAPK_OUT}/vapk.apk"
	${ADB} -s "$ANDROID_SERIAL" install -r ${VAPK_OUT}/vapk.apk
*/
}

fn check_dependencies() {

	// Validate V install
	vexe := vxt.vexe()
	if vexe == '' {
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