import common.testing

const the_executable = testing.prepare_executable('head')

const cmd = testing.new_paired_command('head', the_executable)

fn get_file_name() string {
	return 'head.v'
}

fn get_file_regex() string {
	return '*.v'
}

fn test_help_and_version() ? {
	cmd.ensure_help_and_version_options_work() ?
}

fn test_lines() {
	file := get_file_name()
	assert cmd.same_results('$file')

	assert cmd.same_results('--lines=50 $file')
	assert cmd.same_results('--lines=-50 $file')

	assert cmd.same_results('-n 50 $file')
	assert cmd.same_results('-n -50 $file')
}

fn test_bytes() {
	file := get_file_name()
	assert cmd.same_results('--bytes=50 $file')
	assert cmd.same_results('--bytes=-50 $file')
	assert cmd.same_results('-c 50 $file')
	assert cmd.same_results('-c -50 $file')
}

fn test_multipliers() {
	file := get_file_name()
	assert cmd.same_results('--lines=100b $file')
	assert cmd.same_results('--lines=30k $file')
	assert cmd.same_results('--lines=30K $file')
	assert cmd.same_results('--lines=30kB $file')
	assert cmd.same_results('--lines=30KB $file')
	assert cmd.same_results('--lines=1M $file')
	assert cmd.same_results('--lines=4MB $file')
}

fn test_null_seperator() {
	file := get_file_name()
	assert cmd.same_results('-z $file')
}

fn test_verbose() {
	file := get_file_name()
	assert cmd.same_results('-v $file')
}

fn test_quiet() {
	file := get_file_regex()
	assert cmd.same_results('-q $file')
}

fn test_multiple_files() {
	file := get_file_regex()
	assert cmd.same_results('$file')
}

fn test_rand() {
	assert cmd.same_results('-n 10 /dev/urandom | wc -l')
	assert cmd.same_results('-n 10b /dev/urandom | wc -l')
	assert cmd.same_results('-n 10kB /dev/urandom | wc -l')
	assert cmd.same_results('-n 10K /dev/urandom | wc -l')

	assert cmd.same_results('-c 10 /dev/urandom | wc -c')
	assert cmd.same_results('-c 10b /dev/urandom | wc -c')
	assert cmd.same_results('-c 10kB /dev/urandom | wc -c')
	assert cmd.same_results('-c 10K /dev/urandom | wc -c')
}
