#!/bin/bash
set -eo pipefail

# ldd /app/llama-server* ||:
# ldd /app/lib/* ||:

export LD_LIBRARY_PATH=/lib64:/usr/lib:/usr/lib64:/app/lib
NEEDED_LIBS=( $(ldd /app/llama-server* | grep '=> /app' | sed -rE 's/[^>]+>\s+([^ ]+).*/\1/') )

echo "Needed libraries: ${NEEDED_LIBS[@]}"

for lib in $(ls /app/lib/*); do
    if ! [[ " ${NEEDED_LIBS[@]} " =~ " ${lib} " ]]; then
        echo "Removing unused library: $lib"
        rm -f "$lib"
    else
        echo "Retaining library: $lib"
    fi
done

REMAINING=$(du -sh /app/lib | cut -d' ' -f1)
echo Shipping ${REMAINING} in libraries
