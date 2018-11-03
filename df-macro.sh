#!/bin/bash

function die() {
  echo "$@" >&2; exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--destination)
      destination="$2"
      shift
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

output_file_name="$(basename $macro_file .macro).mak"
mak_file_base="$(dirname $macro_file)"

function process_mak_file() {
  mak_file=$1
  sed -e "1 d;$ d" "$mak_file_base/$mak_file"
}

function process_macro_line() {
  words=($1)
  case ${words[0]} in
    mak)
      process_mak_file "${1:4}"
      ;;
    *)
      printf "\t\t$1\n\tEnd of group\n"
      ;;
  esac
}

function process_macro_file() {
  macro_file=$1

  while IFS= read -r line; do
    # ignore blank lines and comments
    if [[ -z $line || ${line:0:1} == "#" ]]; then
      continue
    fi

    process_macro_line "$line"
  done < "$macro_file"
}

cat > "$destination/$output_file_name" << EOF
$(basename $output_file_name .mak)
$(process_macro_file $macro_file)
END of macro
EOF

printf " => output: $destination/$output_file_name\n"
