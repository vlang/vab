import os
import vab.cli

const test_dir = os.join_path(os.vtmp_dir(), 'vab', 'tests', 'cli')
const a1 = ['vab', test_dir, '-o', '/path/to/out']
const a2 = ['vab', '-o', '/path/to/out', test_dir]
const a3 = ['vab', '-f', '-d vab_xyz', test_dir, '-o', '/path/to/out']

fn test_find_input() {
	os.rm(test_dir) or {}
	os.mkdir_all(test_dir)!

	input1, args1 := cli.input_from_args(a1)
	assert input1 == test_dir
	assert args1 == ['vab', '-o', '/path/to/out']

	input2, args2 := cli.input_from_args(a2)
	assert input2 == test_dir
	assert args2 == ['vab', '-o', '/path/to/out']

	input3, args3 := cli.input_from_args(a3)
	assert input3 == test_dir
	assert args3 == ['vab', '-f', '-d vab_xyz', '-o', '/path/to/out']
}
