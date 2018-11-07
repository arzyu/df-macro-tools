#!/bin/bash

set -e

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

if [[ -z "$macro_file" ]]; then
	die "No input file *.macro"
fi

if [[ -z "$destination" ]]; then
	destination="$(pwd)"
fi

if [[ -z "$output_file" ]]; then
	output_file=$(basename $macro_file .macro).mak
fi

if [[ -z "$stdout" ]]; then
	stdout="no"
fi

base_dir=$(dirname "$macro_file")

function process_mak_file() {
	local mak_file=$1
	sed -e '1d; $d' "$base_dir/$mak_file"
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
	local pattern_flip='*([[:space:]])flip+([[:space:]])@(horizontal|h|vertical|v)+([[:space:]])*'
	local pattern_round='*([[:space:]])round?(+([[:space:]])?(2x|4x|4xr))+([[:space:]])*'
	local pattern_use='*([[:space:]])use+([[:space:]])*'

	shopt -s extglob

	if [[ "$line" == $pattern_mak ]]; then
		## ${line##${pattern_mak:0:-1}} is supported after bash v4.2
		local mak_file=$(trim_left "$line" "${pattern_mak:0:${#pattern_mak}-1}")
		process_mak_file "$mak_file"

	elif [[ "$line" == $pattern_macro ]]; then
		local macro_file=$(trim_left "$line" "${pattern_macro:0:${#pattern_macro}-1}")
		$0 --stdout "$base_dir/$macro_file" | sed -e '1d; $d'

	elif [[ "$line" == $pattern_n_times ]]; then
		local macro_line=$(trim_left "$line" "${pattern_n_times:0:${#pattern_n_times}-1}")
		local compiled_content=$(process_macro_line "$macro_line")
		local pattern_n_prefix='*([[:space:]])'
		local pattern_n_suffix='+([[:space:]])\*+([[:space:]])*'
		local n=$(trim "$line" "$pattern_n_prefix" "$pattern_n_suffix")

		printf "$compiled_content\n%.0s" $(seq 1 $n)

	elif [[ "$line" == $pattern_rotate ]]; then
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
		esac

		transform_cursor "$compiled_content" "${replacements[@]}"

	elif [[ "$line" == $pattern_flip ]]; then
		local macro_line=$(trim_left "$line" "${pattern_flip:0:${#pattern_flip}-1}")
		local compiled_content=$(process_macro_line "$macro_line")
		local pattern_flip_axis_prefix='*([[:space:]])flip+([[:space:]])'
		local pattern_flip_axis_suffix='+([[:space:]])*'
		local flip_axis=$(trim "$line" "$pattern_flip_axis_prefix" "$pattern_flip_axis_suffix")

		local replacements

		case $flip_axis in
			h|horizontal) replacements=(UP LEFT DOWN RIGHT);;
			v|vertical) replacements=(DOWN RIGHT UP LEFT);;
		esac

		transform_cursor "$compiled_content" "${replacements[@]}"

	elif [[ "$line" == $pattern_round ]]; then
		local macro_line=$(trim_left "$line" "${pattern_round:0:${#pattern_round}-1}")
		local pattern_round_with_param='*([[:space:]])round+([[:space:]])@(2x|4x|4xr)+([[:space:]])*'
		local pattern_round_x_prefix='*([[:space:]])round+([[:space:]])'
		local pattern_round_x_suffix='+([[:space:]])*'
		local round_x

		if [[ "$line" == $pattern_round_with_param ]]; then
			round_x=$(trim "$line" "$pattern_round_x_prefix" "$pattern_round_x_suffix")
		fi

		round_x=${round_x:-4x}

		case $round_x in
			2x)
				process_macro_file <<-EOF
					$macro_line
					rotate south $macro_line
				EOF
				;;
			4x)
				process_macro_file <<-EOF
					$macro_line
					rotate east $macro_line
					rotate south $macro_line
					rotate west $macro_line
				EOF
				;;
			4xr)
				process_macro_file <<-EOF
					$macro_line
					rotate west $macro_line
					rotate south $macro_line
					rotate east $macro_line
				EOF
				;;
		esac

	elif [[ "$line" == $pattern_use ]]; then
		local def_name=$(trim_left "$line" "${pattern_use:0:${#pattern_use}-1}")
		process_macro_file <<< "$(get_def_content "$def_name")"

	else
		local raw_macro=$(trim_left "$1" '*([[:space:]])')

		if [[ "$raw_macro" != [A-Z]* ]]; then
			die "Syntax error: [$raw_macro]"
		fi

		printf "\t\t%s\n\tEnd of group\n" "$raw_macro"
	fi

	shopt -u extglob
}

function process_macro_file() {
	local macro_file=${1:-/dev/stdin}
	local content=$(< "$macro_file")
	local pattern_comment='*([[:space:]])#*'

	shopt -s extglob

	for (( i=0, len=$(wc -l <<< "$content"); i < len; i++ )) ; do
		IFS= read -r line

		## ignore blank lines and comments
		if [[ -z "$line" || "$line" == $pattern_comment ]]; then
			continue
		fi

		process_macro_line "$line"
	done <<< "$content"

	shopt -u extglob
}

function get_def_content() {
	def_name=$1
	sed -En \
		-e "
			:start
			/[[:space:]]*def[[:space:]]+$def_name[[:space:]]+{/ {
				/[[:space:]]*}/! {
					N
					b start
				}
				p
			}
		" \
		<<< "$defs" | \
	sed '1d; $d'
}

function get_defs() {
	macro_file=${1:-/dev/stdin}
	sed -En \
		-e '
			:start
			/[[:space:]]*def[[:space:]]+.+[[:space:]]+{/ {
				/[[:space:]]*}/! {
					N
					b start
				}
				p
			}
		' \
		"$macro_file"
}

function prepare_macro_file() {
	macro_file=${1:-/dev/stdin}
	sed -En \
		-e '
			:start
			/[[:space:]]*def[[:space:]]+.+[[:space:]]+{/ {
				/[[:space:]]*}/! {
					N
					b start
				}
				d
			}
			p
			d
		' \
		"$macro_file"
}

defs=$(get_defs "$macro_file")
prepared_macro_file=$(prepare_macro_file "$macro_file")

{ output=$(< /dev/stdin); } <<-EOF
	$(basename $output_file .mak)
	$(process_macro_file <<< "$prepared_macro_file")
	End of macro
EOF

if [[ "$stdout" == "yes" ]]; then
	printf "%s\n" "$output"
else
	printf "%s\n" "$output" > "$destination/$output_file"
	printf " => output: $destination/$output_file\n"
fi
