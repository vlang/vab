module android

import os

fn verbosity_print_cmd(args []string, verbosity int) {
	cmd := args.join(' ')
	if verbosity > 1 {
		println('Running ${args[0]}')
		if verbosity > 2 {
			println(cmd)
		}
	}
}

fn run_else_exit(args []string) string {
	cmd := args.join(' ')
	res := os.exec(cmd) or { os.Result{1,''} }
	if res.exit_code > 0 {
		eprintln('${args[0]} failed with exit code ${res.exit_code}')
		eprintln(res.output)
		exit(1)
	}
	return res.output
}
