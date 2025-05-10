// vtest vflags: -d vab_no_notices
import os
import term
import rand
import toml
import sync.pool
import v.util.diff
import vab.vxt
import vab.vabxt
import runtime

const vab_home = os.real_path(os.dir(os.dir(@FILE)))
const vab_test_dirs = [
	os.join_path(vab_home, 'tests'),
]
const vexe = vxt.vexe()
const vab_exe = vabxt.vabexe()

const should_autofix = os.getenv('VAUTOFIX') != ''
const empty_toml_map = map[string]toml.Any{}

fn test_all() {
	mut jobs := []TOMLTestJob{}

	for vab_test_dir in vab_test_dirs {
		toml_files := os.walk_ext(vab_test_dir, '.toml')
		for toml_file in toml_files {
			jobs << TOMLTestJob{
				env_vars: {
					'VCOLORS': 'never'
				}
				job_file: toml_file
			}
		}
	}

	mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
	pp.work_on_items(jobs)
	for job_res in pp.get_results[TOMLTestJobResult]() {
		if !job_res.success {
			println('============')
			println('failed cmd: `${job_res.command}`')
			println('expected_out_path: ${job_res.expected_out_path}')
			println('job file: ${job_res.job.job_file}')

			println('============')
			if job_res.expected != job_res.found {
				println('expected:')
				println(job_res.expected)
				println('============')
				println('found:')
				println(job_res.found)
				println('============\n')
				diff_content(job_res.expected, job_res.found)
			} else {
				println('exit code from running `${job_res.command}` did not match the expected. Expected: ${job_res.expected_exit_code}, got: ${job_res.exit_code}')
			}
			println('============\n')
			job_file_contents := os.read_file(job_res.job.job_file) or { panic(err) }
			println('${job_file_contents}')
			println('============')
			assert false
		}
	}
	assert true
}

pub struct TOMLTestJob {
	env_vars map[string]string
	job_file string
}

pub struct TOMLTestJobResult {
	success            bool
	job                TOMLTestJob
	command            string
	expected           string
	expected_out_path  string
	found              string
	expected_exit_code int
	exit_code          int
}

fn async_run(mut pp pool.PoolProcessor, idx int, wid int) &TOMLTestJobResult {
	item := pp.get_item[TOMLTestJob](idx)
	return sync_run(item)
}

fn sync_run(job TOMLTestJob) &TOMLTestJobResult {
	for key, value in job.env_vars {
		os.setenv(key, value, true)
	}

	doc := toml.parse_file(job.job_file) or { panic(err) }
	mut execute := doc.value_opt('execute') or {
		panic('TOML config file needs a top-level `execute` entry')
	}.string()
	expect_exit_code := doc.value('expect.exit_code').default_to(0).int()
	diff_from_line := doc.value('compare.output.from_line').default_to(0).int()
	ignore_lines_starting_with := ['notice:', 'details:', ' ']

	expected_out_path := job.job_file.replace('.toml', '.out')

	env_vars_tm := doc.value('env').default_to(empty_toml_map).as_map()
	env_vars := env_vars_tm.as_strings()
	for key, value in env_vars {
		os.setenv(key, value, true)
	}

	if !execute.starts_with('vab') || execute.contains(';') || execute.contains('&')
		|| execute.contains('|') {
		panic('Only single vab commands allowed')
	}
	os.unsetenv('ANDROID_SERIAL')
	res := os.execute(execute.replace_once('vab', vab_exe))

	mut expected := ''
	expected = os.read_file(expected_out_path) or { panic(err) }
	expected = clean_line_endings(expected)
	mut found := clean_line_endings(res.output)
	if diff_from_line != 0 {
		lines := found.split_into_lines()
		if diff_from_line > 0 {
			found = lines#[diff_from_line..].join('\n')
		} else {
			found = lines#[lines.len + diff_from_line..].join('\n')
		}
	}

	if ignore_lines_starting_with.len > 0 {
		mut filtered := []string{}
		for line in found.split_into_lines() {
			mut ignore := false
			for ignore_string in ignore_lines_starting_with {
				if line.starts_with(ignore_string) {
					ignore = true
					break
				}
			}
			if !ignore {
				filtered << line
			} else {
				println('ignoring line "${line}"')
			}
		}
		found = filtered.join('\n')
	}

	success := expected == found && res.exit_code == expect_exit_code

	if expected != found {
		if should_autofix {
			if !os.exists(expected_out_path) {
				os.create(expected_out_path) or { panic(err) }
			}
			os.write_file(expected_out_path, found) or { panic(err) }
		}
	}

	return &TOMLTestJobResult{
		success:            success
		job:                job
		command:            execute
		expected:           expected
		expected_out_path:  expected_out_path
		found:              found
		expected_exit_code: expect_exit_code
		exit_code:          res.exit_code
	}
}

fn clean_line_endings(s string) string {
	mut res := s.trim_space()
	res = res.replace(' \n', '\n')
	res = res.replace(' \r\n', '\n')
	res = res.replace('\r\n', '\n')
	res = res.trim('\n')
	return res
}

fn diff_content(s1 string, s2 string) {
	diff_cmd := diff.find_working_diff_command() or { return }
	println(term.bold(term.yellow('diff: ')))
	println(diff.color_compare_strings(diff_cmd, rand.ulid(), s1, s2))
	println('============\n')
}
