module java

import os
import regex

// version returns the version of your java install, otherwise empty string
pub fn version() string {
	// If JAVA_HOME is provided we use that to obtain a full path to the java executables
	mut javac := 'javac'
	mut java := 'java'
	java_home := os.getenv('JAVA_HOME')
	if java_home != '' {
		bin := os.getenv('JAVA_HOME').trim_right(os.path_separator)+os.path_separator+'bin'
		if os.is_executable(bin+os.path_separator+'javac') {
			javac = bin+os.path_separator+'javac'
		}
		if os.is_executable(bin+os.path_separator+'java') {
			java = bin+os.path_separator+'java'
		}
	}

	mut version := ''

	// Fast - but not most reliable way
	java_version := os.exec(javac+' -version') or { os.Result{1,''} }
	output := java_version.output
	mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
	start, _ := re.match_string(output)
	if start >= 0 && re.groups.len > 0 {
		version = output[re.groups[0]..re.groups[1]]
	}

	// Slow - but more reliable way, using Java itself
	if version == '' {
		java_source := 'public class JavaVersion { public static void main(String[] args) { System.out.format("%s", System.getProperty("java.version")); } }'
		java_source_dir := os.temp_dir()+os.path_separator
		java_source_exe := 'JavaVersion'
		java_source_file := java_source_exe+'.java'
		pwd := os.getwd()
		os.chdir(java_source_dir)
		os.write_file(java_source_file, java_source) or { return '' }
		if os.system(javac+' $java_source_file') == 0 {
			r := os.exec(java+' $java_source_exe') or { return '' }
			version = r.output
		}
		os.chdir(pwd)
	}

	return version
}