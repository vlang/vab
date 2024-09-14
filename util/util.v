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
pub fn ensure_path(path string) ! {
	if !os.exists(path) {
		os.mkdir_all(path) or {
			return error('${@MOD}.${@FN}: error while making directory "${path}":\n${err}')
		}
	}
}

pub fn vab_error(msg string, details Details) {
	eprintln('${color(.error, bold('error:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, 'details:')}\n${details.details}')
	}
}

pub fn vab_warning(msg string, details Details) {
	eprintln('${color(.warning, bold('warning:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, 'details:')}\n${details.details}')
	}
}

@[if !vab_no_notice ?]
pub fn vab_notice(msg string, details Details) {
	println('${color(.notice, bold('notice:'))} ${msg}')
	if details.details != '' {
		eprintln('${color(.details, 'details:')}\n${details.details}')
	}
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
			term.magenta(msg)
		}
		.notice {
			term.yellow(msg)
		}
		.details {
			term.bright_blue(msg)
		}
		else {
			msg
		}
	}
}
