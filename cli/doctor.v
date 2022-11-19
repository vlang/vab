module cli

import os
import vab.vxt
import vab.java
import vab.android
import vab.android.sdk
import vab.android.ndk
import vab.android.env

// doctor prints various useful information to the shell to aid
// diagnosticing the work environment.
pub fn doctor(opt Options) {
	sdkm := env.sdkmanager()
	env_managable := env.managable()
	env_vars := os.environ()

	// Validate Android `sdkmanager` tool
	// Just warnings/notices as `sdkmanager` isn't used to in the build process.
	if sdkm == '' {
		eprintln('No "sdkmanager" could be detected.\n')
		if env_managable {
			eprintln('You can run `${exe_short_name} install cmdline-tools` to install it.')
		}
		eprintln('You can set the SDKMANAGER env variable or try your luck with `${exe_short_name} install auto`.')
		eprintln('Please see https://stackoverflow.com/a/61176718/1904615 for more help.\n')
	} else {
		if !env_managable {
			sdk_is_writable := os.is_writable(sdk.root())
			if !sdk_is_writable {
				eprintln('The SDK at "${sdk.root()}" is not writable.')
				eprintln("`${exe_short_name}` is not able to control the SDK and it's dependencies.")
			} else {
				eprintln('The detected `sdkmanager` seems outdated or incompatible with the Java version used.')
				eprintln("For `${exe_short_name}` to control it's own dependencies, please update `sdkmanager` found in:")
				eprintln('"${sdkm}"')
				eprintln('or use a Java version that is compatible with your `sdkmanager`.')
				eprintln('You can set the SDKMANAGER env variable or try your luck with `${exe_short_name} install auto`.')
				eprintln('Please see https://stackoverflow.com/a/61176718/1904615 for more help.\n')
			}
		}
	}

	// Try to warn about broken Java distributions like IBM's Semeru
	java_exe := java.jre_java_exe()
	if os.is_executable(java_exe) {
		java_version := os.execute(java_exe + ' -version')
		if java_version.exit_code == 0 {
			output := java_version.output
			if !(output.contains('OpenJDK') || output.contains('Java(TM)')) {
				eprintln("Notice: The detected Java Runtime Environment may be incompatible with some of the Android SDK tools needed. We recommend using OpenJDK's Temurin release from https://adoptium.net")
				eprintln('Your Java shows:')
				eprintln(output)
			}
		}
	}

	mut default_base_files_path := android.default_base_files_path
	if opt.package_overrides_path != '' {
		default_base_files_path = opt.package_overrides_path
	}

	// vab section
	println('${exe_short_name}
	Version ${exe_version} ${exe_git_hash}
	Path "${exe_dir}"
	Base files "${default_base_files_path}"')

	// Shell environment
	print_var_if_set := fn (vars map[string]string, var_name string) {
		if var_name in vars {
			println('\t${var_name}=' + os.getenv(var_name))
		}
	}
	println('env')
	for env_var in vab_env_vars {
		print_var_if_set(env_vars, env_var)
	}

	keytool := java.jdk_keytool() or { 'N/A' }
	// Java section
	println('Java
	JDK
		Version ${java.jdk_version()}
		Path "${java.jdk_root()}"
		Keytool "${keytool}"')

	// Android section
	println('Android
	ENV
		sdkmanager "${sdkm}"
		sdkmanager.version "${env.sdkmanager_version()}"
		Managable ${env_managable}
	SDK
		Path "${sdk.root()}"
		Writable ${os.is_writable(sdk.root())}
		APIs available ${sdk.apis_available()}
	NDK
		Version ${opt.ndk_version}
		Path "${ndk.root()}"
		Side-by-side ${ndk.is_side_by_side()}
		min API level available ${ndk.min_api_available(opt.ndk_version)}
		max API level available ${ndk.max_api_available(opt.ndk_version)}')
	apis_by_arch := ndk.available_apis_by_arch(opt.ndk_version)
	for arch, api_levels in apis_by_arch {
		println('\t\t${arch:-11} ${api_levels}')
	}
	println('\tBuild
		API ${opt.api_level}
		Build-tools ${opt.build_tools}
	Packaging
		Format ${opt.package_format}')

	if env.has_bundletool() {
		println('\t\tBundletool "${env.bundletool()}"')
	}
	if env.has_aapt2() {
		println('\t\tAAPT2 "${env.aapt2()}"')
	}

	if opt.keystore != '' || opt.keystore_alias != '' {
		println('\tKeystore')
		println('\t\tFile ${opt.keystore}')
		println('\t\tAlias ${opt.keystore_alias}')
	}
	// Product section
	println('Product
	Name "${opt.app_name}"
	Package ID "${opt.package_id}"
	Output "${opt.output}"')

	// V section
	println('V
	Version ${vxt.version()} ${vxt.version_commit_hash()}
	Path "${vxt.home()}"')
	if opt.v_flags.len > 0 {
		println('\tFlags ${opt.v_flags}')
	}
	// Print output of `v doctor` if v is found
	if vxt.found() {
		println('')
		v_cmd := [
			vxt.vexe(),
			'doctor',
		]
		v_res := os.execute(v_cmd.join(' '))
		out_lines := v_res.output.split('\n')
		for line in out_lines {
			println('\t${line}')
		}
	}
}
