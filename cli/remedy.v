module cli

import semver
import vab.util
import vab.android
import vab.extra

// doctor_remedy notifies of known errors and mismatches of various Android SDK/NDK bugs, if detected.
pub fn doctor_remedy(opts android.OptionTypes, err_str string) {
	match opts {
		android.PackageOptions {
			notify_known_package_errors(opts, err_str)
		}
		else {}
	}
}

fn callsite_extra_command(cmd string) string {
	if cmd.starts_with(extra.command_prefix + '-') {
		return '${extra.command_prefix} ${cmd.all_after(extra.command_prefix + '-')}'
	}
	return cmd
}

fn notify_known_package_errors(opt android.PackageOptions, err_str string) {
	if opt.api_level.i16() >= 35 {
		if build_tools_semantic_version := semver.from(opt.build_tools) {
			build_tools_version := '34.0.0'
			if build_tools_semantic_version.satisfies('<${build_tools_version}') {
				symptoms_aab := "\taapt2 E 10-15 19:10:38 93691 93691 LoadedArsc.cpp:96] RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data.
\taapt2 E 10-15 19:10:38 93691 93691 ApkAssets.cpp:500] Failed to load 'resources.arsc' in APK '.../platforms/android-35/android.jar'."
				symptoms_apk := "\taapt E 10-15 18:51:31 89712 89712] Entry offset at index 1335 points outside the Type's boundaries
\t.../AndroidManifest.xml:13: error: Error: No resource found that matches the given name (at 'theme' with value '@android:style/Theme.NoTitleBar.Fullscreen').
\t.../res/values/styles.xml:4: error: Error retrieving parent for item: No resource found that matches the given name 'android:Theme.Holo.Light.DarkActionBar'."
				symptoms := if opt.format == .aab { symptoms_aab } else { symptoms_apk }
				util.vab_notice('Using build-tools < ${build_tools_version} with Android API level >= ${opt.api_level} is known to cause package build errors',
					details:
						'Symptoms:\n${symptoms}\nIt can usually be fixed by installing and using build-tools >= ${build_tools_version}' +
						'\nTry:\n\tvab install "build-tools;${build_tools_version}"\n\t${callsite_extra_command(exe_short_name)} --build-tools "${build_tools_version}" ...'
				)
			}
		}
	}
}
