#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

SRCS=(
    src/syscall.s
    src/mem.s
    src/sha256.s
    src/config.s
    src/http.s
    src/router.s
    src/static.s
    src/markdown.s
    src/template.s
    src/store.s
    src/handlers.s
    src/studio.s
    src/net_epoll.s
    src/cli.s
    src/main.s
)

OBJS=()
for s in "${SRCS[@]}"; do
    base=$(basename "$s" .s)
    obj="build/${base}.o"
    as --64 -I src --gdwarf-5 -o "$obj" "$s"
    OBJS+=("$obj")
done

ld -static -z noexecstack -o asmblog "${OBJS[@]}"
if [ "${1:-}" = "--strip" ]; then
    strip --strip-all asmblog
fi
ls -lh asmblog
file asmblog
