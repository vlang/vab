// Copyright(C) 2023 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module util

import os
import term

const term_has_color_support = term.can_show_color_on_stderr() && term.can_show_color_on_stdout()

pub enum MessageKind {
	neutral
	error
	warning
	notice
	details
}

@[params]
pub struct Details {
pub:
	details string
}

// ensure_path creates `path` if it does not already exist.
@[deprecated: 'use paths.ensure() instead']
@[deprecated_after: '2025-10-02']
pub fn ensure_path(path string) ! {
	if !os.exists(path) {
		os.mkdir_all(path) or {
			return error('${@MOD}.${@FN}: error while making directory "${path}":\n${err}')
		}
	}
}

// vab_error prints `msg` prefixed with `error:` in red + `details` to STDERR.
pub fn vab_error(msg string, details Details) {
	eprintln('${color(.error, bold('error:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, bold('details:'))}\n${format_details(details.details)}')
	}
}

// vab_warning prints `msg` prefixed with `error:` in yellow + `details` to STDERR.
pub fn vab_warning(msg string, details Details) {
	eprintln('${color(.warning, bold('warning:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, bold('details:'))}\n${format_details(details.details)}')
	}
}

// vab_notice prints `msg` prefixed with `notice:` in magenta + `details` to STDERR.
// vab_notice can be disabled with `-d vab_no_notice` at compile time.
@[if !vab_no_notices ?]
pub fn vab_notice(msg string, details Details) {
	println('${color(.notice, bold('notice:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, bold('details:'))}\n${format_details(details.details)}')
	}
}

fn format_details(s string) string {
	return '  ${s.replace('\n', '\n  ')}'
}

fn bold(msg string) string {
	if !term_has_color_support {
		return msg
	}
	return term.bold(msg)
}

fn color(kind MessageKind, msg string) string {
	if !term_has_color_support {
		return msg
	}
	return match kind {
		.error {
			term.red(msg)
		}
		.warning {
			term.yellow(msg)
		}
		.notice {
			term.magenta(msg)
		}
		.details {
			term.bright_blue(msg)
		}
		else {
			msg
		}
	}
}
