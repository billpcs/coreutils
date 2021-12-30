import os
import io
import math
import math.util
import common

const (
	app_name           = 'head'
	app_description    = 'output the first part of files'
	bytes_description  = "print the first <string> bytes of each file; with the leading '-', print all but the last <string> bytes of each file"
	lines_description  = "print the first <string> lines instead of the first 10; with the leading '-', print all but the last <string> lines of each file"
	stdin_string       = 'standard input'
	seperator_nul      = `\0`
	seperator_new_line = `\n`
	default_lines      = u64(10)
	max_chunk          = 16 * 1024
)

enum ShowType {
	bytes
	lines
}

enum HeaderMode {
	standard
	quiet
	verbose
}

struct Settings {
	num             u64
	is_positive     bool
	typ             ShowType
	verbosity       HeaderMode
	zero_terminated bool
	fnames          []string
}

struct FileData {
	name string
mut:
	fd os.File
	br io.BufferedReader
}

fn main() {
	head(args())
}

fn print_exit(s string) {
	eprintln(s)
	exit(1)
}

fn head(settings Settings) {
	incoming_fnames := settings.fnames
	fnames := if incoming_fnames.len < 1 { [stdin_string] } else { incoming_fnames }
	length := fnames.len
	print_header := (settings.verbosity == .verbose || fnames.len > 1)
		&& settings.verbosity != .quiet

	for i, fname in fnames {
		if os.is_dir(fname) {
			eprintln("$app_name: error reading '$fname': Is a directory")
			continue
		}

		mut file := get_fd_by_filename(fname) or {
			eprintln("$app_name: cannot open '$fname' for reading: No such file or directory")
			continue
		}

		if print_header {
			println('==> $fname <==')
		}

		mut br := io.new_buffered_reader(io.BufferedReaderConfig{ reader: file })
		mut data := FileData{fname, file, br}

		typ := settings.typ
		positive := settings.is_positive

		if typ == .bytes {
			if positive {
				head_of_bytes(mut data, settings)
			} else {
				head_of_bytes_elide_tail(mut data, settings)
			}
		} else if typ == .lines {
			if positive {
				head_of_lines(mut data, settings)
			} else {
				head_of_lines_elide_tail(mut data, settings)
			}
		}

		if (i != length - 1) && print_header {
			// prints newline after everything except the last one
			println('')
		}
	}
}

fn head_of_lines(mut data FileData, settings Settings) {
	units := settings.num
	if settings.zero_terminated {
		head_of_lines_with_sep(mut data, units, seperator_nul)
	} else {
		head_of_lines_with_sep(mut data, units, seperator_new_line)
	}
}

fn head_of_lines_elide_tail(mut data FileData, settings Settings) {
	new_settings := Settings{
		num: number_of_units_to_print(data.name, settings)
		is_positive: true
		typ: settings.typ
		verbosity: settings.verbosity
		zero_terminated: settings.zero_terminated
		fnames: settings.fnames
	}
	head_of_lines(mut data, new_settings)
}

fn head_of_lines_with_sep(mut data FileData, units u64, sep byte) {
	mut stdout := os.stdout()
	mut buf := []byte{len: max_chunk}
	mut counted := u64(0)
	for {
		n_read := data.br.read(mut buf) or { return }

		for i in 0 .. n_read {
			if _unlikely_(buf[i] == sep) {
				counted += 1
			}
			if _unlikely_(counted == units) {
				stdout.write(buf[0..i + 1]) or { print_exit('$app_name: error writing $data.name') }
				stdout.flush()
				return
			}
		}

		if n_read > 0 {
			stdout.write(buf[0..n_read]) or { print_exit('$app_name: error writing $data.name') }
		}
	}
	stdout.flush()
	return
}

fn head_of_bytes(mut data FileData, settings Settings) {
	// we can't create an array with size u64
	// so we loop as many times a required to reach the
	// required byte limit using a smaller buffer
	mut stdout := os.stdout()
	mut remaining_bytes := settings.num
	mut premade_buffer := []byte{len: max_chunk}

	for remaining_bytes > 0 {
		size := if remaining_bytes > max_chunk { max_chunk } else { int(remaining_bytes) }
		n_read := data.br.read(mut premade_buffer) or { break }
		to_write := util.imin(size, n_read)
		stdout.write(premade_buffer[0..to_write]) or {
			eprintln('$app_name: error writing $data.name')
			exit(1)
		}
		remaining_bytes -= u64(size)
	}
	stdout.flush()
}

fn head_of_bytes_elide_tail(mut data FileData, settings Settings) {
	n_elide := settings.num

	mut stdout := os.stdout()

	mut buf_array := [][]byte{}

	// find how many buffers we need in order
	// to buffer enough to start printing
	remainder := int(max_chunk - (n_elide % max_chunk))
	n_elide_rounded := n_elide + u64(remainder)
	n_bufs := int(n_elide_rounded / max_chunk + 1)

	mut buffered_enough := false
	mut read_index := 0
	mut echo_index := 1
	mut n_read := 0

	for {
		if !buffered_enough {
			buf_array << []byte{len: max_chunk}
		}

		n_read = data.br.read(mut buf_array[read_index]) or {
			eprintln(err)
			0
		}

		if read_index == n_bufs - 1 {
			buffered_enough = true
		}

		if buffered_enough {
			stdout.write(buf_array[echo_index][0..n_read]) or {}
		}

		read_index = echo_index
		echo_index = (echo_index + 1) % n_bufs

		if n_read < max_chunk {
			break
		}
	}

	if remainder != 0 {
		if buffered_enough {
			bytes_left := max_chunk - n_read
			if remainder < bytes_left {
				stdout.write(buf_array[read_index][n_read..n_read + remainder]) or {}
			} else {
				stdout.write(buf_array[read_index][n_read..n_read + bytes_left]) or {}
				stdout.write(buf_array[echo_index][0..remainder - bytes_left]) or {}
			}
		} else if read_index + 1 == n_bufs {
			sz := n_read - (max_chunk - remainder)
			stdout.write(buf_array[echo_index][0..sz]) or {}
		}
	}
}

fn get_fd_by_filename(fname string) ?os.File {
	return if fname == stdin_string || fname == '-' { os.stdin() } else { os.open(fname) or {
			return err
		} }
}

[inline]
fn count_bytes(bytes []byte, sz int, sep byte) u64 {
	mut count := u64(0)
	for i in 0 .. sz {
		if bytes[i] == sep {
			count += 1
		}
	}
	return count
}

fn count_seperators(fname string, sep byte) u64 {
	mut sz := 1
	mut count := u64(0)
	mut file := get_fd_by_filename(fname) or { exit(1) }
	mut br := io.new_buffered_reader(io.BufferedReaderConfig{ reader: file })
	mut buf := []byte{len: max_chunk}
	for sz > 0 {
		sz = br.read(mut buf) or { return count }
		count += count_bytes(buf, sz, sep)
	}
	return count
}

fn number_of_units_to_print(filename string, settings Settings) u64 {
	// if we have positive unit number we return it directly
	if settings.is_positive {
		return settings.num
	}

	sep := if settings.zero_terminated { seperator_nul } else { seperator_new_line }

	sep_num := count_seperators(filename, sep)
	if settings.num <= sep_num {
		return sep_num - settings.num
	} else {
		return settings.num
	}
}

fn get_multiplier_mappings() map[string]u64 {
	mut multiplier_map := map[string]u64{}
	mut valids_bin := ['K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y']
	for i, bin in valids_bin {
		multiplier_map[bin] = u64(math.pow(1024, i + 1))
	}

	mut valids_dec := ['KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
	for i, dec in valids_dec {
		multiplier_map[dec] = u64(math.pow(1000, i + 1))
	}

	multiplier_map['k'] = u64(1024)
	multiplier_map['kB'] = u64(1000)
	multiplier_map['m'] = u64(1024 * 1024)
	multiplier_map['b'] = u64(512)

	return multiplier_map
}

fn parse_number(str string, typ string) ?(u64, bool) {
	// save the sign information in a
	// different variable, this way we
	// don't have to use i64
	is_positive := !str.starts_with('-')

	// remove the sign from the string
	num_str := str.replace_once('-', '')

	base := num_str.u64()
	temp_multiplier := str.split(base.str())
	if temp_multiplier.len != 2 {
		eprintln("$app_name: invalid number of $typ: '$num_str'")
		exit(1)
	}
	multiplier := temp_multiplier[1]

	if multiplier == '' {
		return base, is_positive
	}

	multiplier_map := get_multiplier_mappings()
	mult := multiplier_map[multiplier]

	if mult > 0 {
		return mult * base, is_positive
	} else {
		eprintln("$app_name: invalid number of $typ: '$num_str'")
		exit(1)
	}

	return base, is_positive
}

fn args() Settings {
	mut fp := common.flag_parser(os.args)
	fp.application(app_name)
	fp.description(app_description)

	bytes_str := fp.string('bytes', `c`, '0', bytes_description)
	lines_str := fp.string('lines', `n`, '0', lines_description)
	quiet := fp.bool('quiet', `q`, false, 'never print headers giving file names')
	verbose := fp.bool('verbose', `v`, false, 'always print headers giving file names')
	zero_terminated := fp.bool('zero', `z`, false, 'line delimiter is NUL, not newline')

	fnames := fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		exit(1)
	}

	mut bytes, b_is_positive := parse_number(bytes_str, 'bytes') or { u64(0), true }
	mut lines, l_is_positive := parse_number(lines_str, 'lines') or { u64(0), true }

	mut typ := ShowType.lines
	mut num := default_lines
	mut pos := true
	mut verbosity := if verbose {
		HeaderMode.verbose
	} else if quiet {
		HeaderMode.quiet
	} else {
		HeaderMode.standard
	}

	if bytes != 0 && lines != 0 {
		// if both exist we have to chose one
		typ = ShowType.lines
		num = lines
		pos = l_is_positive
	} else if bytes != 0 {
		typ = ShowType.bytes
		num = bytes
		pos = b_is_positive
	} else if lines != 0 {
		typ = ShowType.lines
		num = lines
		pos = l_is_positive
	}

	if quiet && verbose {
		// if both exist we have to chose one
		verbosity = .quiet
	}

	ret := Settings{num, pos, typ, verbosity, zero_terminated, fnames}

	return ret
}
