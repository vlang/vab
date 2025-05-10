// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module util

import os
import sync.pool

pub struct ShellJobMessage {
pub:
	std_out string
	std_err string
}

pub struct ShellJob {
pub:
	message  ShellJobMessage
	cmd      []string
	env_vars map[string]string
}

pub struct ShellJobResult {
pub:
	job    ShellJob
	result os.Result
}

// async_run runs all the ShellJobs in `pp` asynchronously.
fn async_run(mut pp pool.PoolProcessor, idx int, wid int) &ShellJobResult {
	job := pp.get_item[ShellJob](idx)
	return sync_run(job)
}

// sync_run runs the `job` ShellJob.
fn sync_run(job ShellJob) &ShellJobResult {
	for key, value in job.env_vars {
		os.setenv(key, value, true)
	}
	if job.message.std_out != '' {
		println(job.message.std_out)
	}
	if job.message.std_err != '' {
		eprintln(job.message.std_err)
	}
	res := run(job.cmd)
	return &ShellJobResult{
		job:    job
		result: res
	}
}

// run_jobs runs all `jobs` jobs either in `parallel` or one after another.
pub fn run_jobs(jobs []ShellJob, parallel bool, verbosity int) ! {
	if parallel {
		mut pp := pool.new_pool_processor(callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results[ShellJobResult]() {
			verbosity_print_cmd(job_res.job.cmd, verbosity)
			if job_res.result.exit_code != 0 {
				return error('${job_res.job.cmd[0]} failed with return code ${job_res.result.exit_code}:\n${job_res.result.output}')
			}
			if verbosity > 2 {
				println('${job_res.result.output}')
			}
		}
	} else {
		for job in jobs {
			verbosity_print_cmd(job.cmd, verbosity)
			job_res := sync_run(job)
			if job_res.result.exit_code != 0 {
				return error('${job_res.job.cmd[0]} failed with return code ${job_res.result.exit_code}:\n${job_res.result.output}')
			}
			if verbosity > 2 {
				println('${job_res.result.output}')
			}
		}
	}
}

// verbosity_print_cmd prints information about the `args` at certain `verbosity` levels.
fn verbosity_print_cmd(args []string, verbosity int) {
	if args.len > 0 && verbosity > 1 {
		cmd_short := args[0].all_after_last(os.path_separator)
		mut output := 'Running ${cmd_short} From: ${os.getwd()}'
		if verbosity > 2 {
			output += '\n' + args.join(' ')
		}
		println(output)
	}
}

fn run(args []string) os.Result {
	res := os.execute(args.join(' '))
	if res.exit_code < 0 {
		return os.Result{1, ''}
	}
	return res
}
