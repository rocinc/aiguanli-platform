#!/bin/bash

set -e
set -o pipefail

# Use jemalloc at runtime
if [ "$USE_JEMALLOC" = "true" ]; then
	export LD_PRELOAD=libjemalloc.so.2
fi

# Ensure PGBIN is set according to PGVERSION env var
if [ -n "$PGVERSION" ]; then
	export PGBIN="/usr/lib/postgresql/$PGVERSION/bin"
	export PATH="$PGBIN:$PATH"
fi

exec "$@"
