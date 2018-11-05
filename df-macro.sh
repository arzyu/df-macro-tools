#!/bin/bash

function die() {
	echo "$@" >&2; exit 1
}

while [[ $# > 0 ]]; do
	case $1 in
		-d|--destination)
			destination="$2"
			shift
			;;
		-o|--output-file)
			output_file="$2"
			shift
			;;
		--stdout)
			stdout="yes"
			;;
		*)
			macro_file="$1"
			;;
	esac

	shift
done

if [[ -z $macro_file ]]; then
	die "No input file *.macro"
fi

if [[ -z $destination ]]; then
	destination="$(pwd)"
fi

if [[ -z $output_file ]]; then
	output_file=$(basename $macro_file .macro).mak
fi

if [[ -z $stdout ]]; then
	stdout="no"
fi

base_dir=$(dirname $macro_file)

function process_mak_file() {
	local mak_file=$1
	sed -e "1 d;$ d" "$base_dir/$mak_file"
}

function trim_left() {
	local string=$1
	local pattern_prefix=$2

	printf "%s" "${string##$pattern_prefix}"
}

function trim() {
	local string=$1
	local pattern_prefix=$2
	local pattern_suffix=$3

	left_trimmed=$(trim_left "$string" "$pattern_prefix")
	printf "%s" "${left_trimmed%%$pattern_suffix}"
}

function transform_cursor() {
	local content=$1; shift
	local replacements=($@)

	sed -n \
		-e "/CURSOR_UP_Z/{p;d;}" \
		-e "/CURSOR_DOWN_Z/{p;d;}" \
		-e "/CURSOR_UP/{s/UP/${replacements[0]}/p;d;}" \
		-e "/CURSOR_RIGHT/{s/RIGHT/${replacements[1]}/p;d;}" \
		-e "/CURSOR_DOWN/{s/DOWN/${replacements[2]}/p;d;}" \
		-e "/CURSOR_LEFT/{s/LEFT/${replacements[3]}/p;d;}" \
		-e p <<< "$content"
}

function process_macro_line() {
	local line=$1

	local pattern_mak='*([[:space:]])mak+([[:space:]])*'
	local pattern_macro='*([[:space:]])macro+([[:space:]])*'
	local pattern_n_times='*([[:space:]])[1-9]*([0-9])+([[:space:]])\*+([[:space:]])*'
	local pattern_rotate='*([[:space:]])rotate+([[:space:]])@(east|e|south|s|west|w)+([[:space:]])*'

	shopt -s extglob

	if [[ $line == $pattern_mak ]]; then
		## ${line##${pattern_mak:0:-1}} is supported after bash v4.2
		local mak_file=$(trim_left "$line" "${pattern_mak:0:${#pattern_mak}-1}")
		process_mak_file "$mak_file"

	elif [[ $line == $pattern_macro ]]; then
		local macro_file=$(trim_left "$line" "${pattern_macro:0:${#pattern_macro}-1}")
		$0 --stdout "$base_dir/$macro_file" | sed -e "1 d;$ d"

	elif [[ $line == $pattern_n_times ]]; then
		local pattern_n_prefix='*([[:space:]])'
		local pattern_n_suffix='+([[:space:]])\*+([[:space:]])*'
		local n=$(trim "$line" "$pattern_n_prefix" "$pattern_n_suffix")
		local macro_line=$(trim_left "$line" "${pattern_n_times:0:${#pattern_n_times}-1}")
		local compiled_content=$(process_macro_line "$macro_line")

		printf "$compiled_content\n%.0s" $(seq 1 $n)

	elif [[ $line == $pattern_rotate ]]; then
		local macro_line=$(trim_left "$line" "${pattern_rotate:0:${#pattern_rotate}-1}")
		local compiled_content=$(process_macro_line "$macro_line")
		local pattern_rotate_to_prefix='*([[:space:]])rotate+([[:space:]])'
		local pattern_rotate_to_suffix='+([[:space:]])*'
		local rotate_to=$(trim "$line" "$pattern_rotate_to_prefix" "$pattern_rotate_to_suffix")

		local replacements

		case $rotate_to in
			e|east) replacements=(RIGHT DOWN LEFT UP);;
			s|south) replacements=(DOWN LEFT UP RIGHT);;
			w|west) replacements=(LEFT UP RIGHT DOWN);;
			*) die "Unexcepted rotate: [$line]"
		esac

		transform_cursor "$compiled_content" "${replacements[@]}"

	else
		printf "\t\t$1\n\tEnd of group\n"
	fi

	shopt -u extglob
}

function process_macro_file() {
	local macro_file=$1

	while IFS= read -r line; do
		# ignore blank lines and comments
		if [[ -z $line || ${line:0:1} == "#" ]]; then
			continue
		fi

		process_macro_line "$line"
	done < "$macro_file"
}

read -r -d '' output <<-EOF
	$(basename $output_file .mak)
	$(process_macro_file $macro_file)
	End of macro
EOF

if [[ $stdout == "yes" ]]; then
	printf "%s\n" "$output"
else
	printf "%s\n" "$output" > "$destination/$output_file"
	printf " => output: $destination/$output_file\n"
fi
