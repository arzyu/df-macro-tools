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

function process_macro_line() {
	local line=$1

	local pattern_mak='*([[:space:]])mak+([[:space:]])*'
	local pattern_macro='*([[:space:]])macro+([[:space:]])*'

	shopt -s extglob

	if [[ $line == $pattern_mak ]]; then
		## ${line##${pattern_mak:0:-1}} is supported after bash v4.2
		local mak_file=${line##${pattern_mak:0:${#pattern_mak}-1}}
		process_mak_file "$mak_file"

	elif [[ $line == $pattern_macro ]]; then
		local macro_file=${line##${pattern_macro:0:${#pattern_macro}-1}}
		$0 --stdout "$base_dir/$macro_file" | sed -e "1 d;$ d"

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
