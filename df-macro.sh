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

if [[ -z $stdout ]]; then
	stdout="no"
fi

output_file_name="$(basename $macro_file .macro).mak"
mak_file_base="$(dirname $macro_file)"

function process_mak_file() {
	local mak_file=$1
	sed -e "1 d;$ d" "$mak_file_base/$mak_file"
}

function process_macro_line() {
	local words=($1)
	case ${words[0]} in
		mak)
			process_mak_file "${1:4}"
			;;
		macro)
			$0 --stdout "$mak_file_base/${1:6}" | sed -e "1 d;$ d"
			;;
		*)
			printf "\t\t$1\n\tEnd of group\n"
			;;
	esac
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
	$(basename $output_file_name .mak)
	$(process_macro_file $macro_file)
	End of macro
EOF

if [[ $stdout == "yes" ]]; then
	printf "%s\n" "$output"
else
	printf "%s\n" "$output" > "$destination/$output_file_name"
	printf " => output: $destination/$output_file_name\n"
fi
