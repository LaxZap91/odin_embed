package embed

import "core:flags"
import "core:fmt"
import "core:os"
import fp "core:path/filepath"
import "core:slice"
import s "core:strings"

FILE_EXT :: []string{".png", ".jpg", ".jpeg", ".wav"}

DATA_WIDTH :: 15

file_as_code_now := proc(image_path: string, image_data: []byte) -> string {
	image_ext := fp.ext(image_path)
	image_base_name := fp.base(image_path)
	image_name, _ := s.substring_to(image_base_name, s.index(image_base_name, image_ext))
	image_name_upper := s.to_upper(image_name)
	image_size := len(image_data)

	builder := s.builder_make(context.temp_allocator)

	fmt.sbprintfln(&builder, "package assets\n")
	fmt.sbprintfln(&builder, "%v_PATH :: `%v`", image_name_upper, image_path)
	fmt.sbprintfln(&builder, "%v_EXT :: \"%v\"\n", image_name_upper, image_ext)
	fmt.sbprintfln(&builder, "%v_SIZE :: %v", image_name_upper, image_size)
	fmt.sbprintfln(&builder, "%v_DATA :: []byte{{", image_name_upper)

	for b, i in image_data {
		if i % DATA_WIDTH == 0 {
			fmt.sbprintf(&builder, "\t")
		}

		fmt.sbprintf(&builder, "%#02X, ", b)

		if i % DATA_WIDTH == (DATA_WIDTH - 1) {
			fmt.sbprintf(&builder, "\n")
		}
	}

	if len(image_data) % DATA_WIDTH != 0 {
		fmt.sbprint(&builder, "\n")
	}

	fmt.sbprintfln(&builder, "}}")
	fmt.sbprintfln(&builder, "%v_PTR := raw_data(%v_DATA)", image_name_upper, image_name_upper)

	return s.to_string(builder)
}

file_as_code_compile_time := proc(image_path: string, image_data: []byte) -> string {
	image_ext := fp.ext(image_path)
	image_base_name := fp.base(image_path)
	image_name, _ := s.substring_to(image_base_name, s.index(image_base_name, image_ext))
	image_name_upper := s.to_upper(image_name)

	builder := s.builder_make(context.temp_allocator)

	fmt.sbprintfln(&builder, "package assets\n")
	fmt.sbprintfln(&builder, "%v_PATH :: `%v`", image_name_upper, image_path)
	fmt.sbprintfln(&builder, "%v_EXT :: \"%v\"\n", image_name_upper, image_ext)
	fmt.sbprintfln(&builder, "%v_DATA :: #load(`..\\..\\` + %v_PATH)", image_name_upper, image_name_upper)
	fmt.sbprintfln(&builder, "%v_PTR := raw_data(%v_DATA)", image_name_upper, image_name_upper)
	fmt.sbprintfln(&builder, "%v_SIZE := i32(len(%v_DATA))", image_name_upper, image_name_upper)

	return s.to_string(builder)
}

export_file_as_code :: proc(input_path, output_path: string, now: bool) {
	input_data, input_err := os.read_entire_file_from_path(input_path, context.temp_allocator)
	if input_err != os.ERROR_NONE {
		msg := os.error_string(input_err)
		fmt.eprintfln("Could not read file %s: %s", input_path, msg)
		return
	}

	input_path, _ := os.clean_path(input_path, context.temp_allocator)

	code: string
	if input_ext := fp.ext(input_path); slice.contains(FILE_EXT, input_ext) {
		if now {
			code = file_as_code_now(input_path, input_data)
		} else {
			code = file_as_code_compile_time(input_path, input_data)
		}
	} else {
		fmt.eprintfln("Extention is unknown: %s", input_ext)
	}

	output, output_create_file_err := os.create(output_path)
	if output_create_file_err != os.ERROR_NONE {
		msg := os.error_string(output_create_file_err)
		fmt.eprintfln("Could not create output file %s: %s", output_path, msg)
		return
	}

	output_write_len, output_write_err := os.write_string(output, code)
	if output_write_err != os.ERROR_NONE {
		msg := os.error_string(output_write_err)
		fmt.eprintfln("Could not write file %s: %s", output_path, msg)
		return
	} else if output_write_len != len(code) {
		fmt.eprintfln("Did not write entire file %v/%v bytes written", output_write_len, len(code))
	}
}

export_dir_as_code :: proc(input_dir, output_dir: string, now: bool) {
	walker := os.walker_create(input_dir)
	defer os.walker_destroy(&walker)

	output_create_dir_err := os.make_directory_all(output_dir)
	if output_create_dir_err != os.ERROR_NONE {
		msg := os.error_string(output_create_dir_err)
		fmt.eprintfln("Could not create output directory %s: %s", fp.dir(output_dir), msg)
		return
	}

	for info in os.walker_walk(&walker) {
		if path, err := os.walker_error(&walker); err != nil {
			msg := os.error_string(err)
			fmt.eprintfln("Failed to walk %s: %s", path, msg)
			continue
		}

		input_file_name, _ := s.substring_to(info.name, s.index(info.name, fp.ext(info.name)))
		output_file, _ := os.join_filename(
			s.concatenate({input_file_name, "_asset"}),
			"odin",
			context.temp_allocator,
		)
		output_path, _ := os.join_path({output_dir, output_file}, context.temp_allocator)
		export_file_as_code(info.fullpath, output_path, now)

		free_all(context.temp_allocator)
	}


}

flag_checker :: proc(
	model: rawptr,
	name: string,
	value: any,
	args_tag: string,
) -> (
	error: string,
) {
	if name == "input" {
		v := value.(string)
		if !os.is_directory(v) {
			error = "Input must be directory."
		}
	} else if name == "output" {
		v := value.(string)
		if !os.is_directory(v) {
			error = "Output must be directory."
		}
	}

	return
}

main :: proc() {
	Options :: struct {
		input:  string `args:"pos=0,required" usage:"Input directory"`,
		output: string `args:"pos=1,required" usage:"Output directory"`,
		now: bool `usage:"Load files now instead of at compile time"`,
	}

	opt: Options
	style: flags.Parsing_Style = .Odin

	flags.Custom_Flag_Checker(flag_checker)
	flags.parse_or_exit(&opt, os.args, style)

	export_dir_as_code(opt.input, opt.output, opt.now)
}
