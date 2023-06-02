#!/bin/bash

set -eo pipefail
shopt -s nullglob

for dir in "${@:2}"; do 
    for f in $(find "$dir" -name "*.js"); do
        out_dir="$1$(dirname "${f#$dir}")"
        mkdir -p "$out_dir"
        echo "export * from './$(basename "$f")';" >> "$out_dir/index.js"
        echo "export * from './$(basename "${f%.js}")';" >> "$out_dir/index.d.ts"
    done
done
