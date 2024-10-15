module cli

import semver
import vab.util

// notify_known_errors notifies when know mismatches of various things is detected.
pub fn notify_known_errors(opt Options) {
	if opt.api_level.i16() >= 33 {
		if build_tools_semantic_version := semver.from(opt.build_tools) {
			if build_tools_semantic_version.satisfies('<35.0.0') {
				symptoms_aab := "\taapt2 E 10-15 19:10:38 93691 93691 LoadedArsc.cpp:96] RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data.
\taapt2 E 10-15 19:10:38 93691 93691 ApkAssets.cpp:500] Failed to load 'resources.arsc' in APK '.../platforms/android-35/android.jar'."
				symptoms_apk := "\taapt E 10-15 18:51:31 89712 89712] Entry offset at index 1335 points outside the Type's boundaries
\t.../res/values/styles.xml:4: error: Error retrieving parent for item: No resource found that matches the given name 'android:Theme.Holo.Light.DarkActionBar'."
				symptoms := if opt.package_format == 'aab' { symptoms_aab } else { symptoms_apk }
				util.vab_notice('Using build-tools < 35.0.0 with Android API level >= 33 is know to cause package build errors',
					details: 'Symptoms output:\n${symptoms}\nIt can usually be fixed by installing and using build-tools >= 35.0.0\nTry:\n\tvab install "build-tools;35.0.0"'
				)
			}
		}
	}
}
