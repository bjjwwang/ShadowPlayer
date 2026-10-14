#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
task_developer_dir="$(xcode-select -p)"
if [[ "$task_developer_dir" == *CommandLineTools ]]; then
    # CLT 26 includes Swift Testing, but SwiftPM does not discover its framework path.
    swift test -Xswiftc -F -Xswiftc "$task_developer_dir/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$task_developer_dir/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$task_developer_dir/Library/Developer/usr/lib" "$@"
else
    swift test "$@"
fi
