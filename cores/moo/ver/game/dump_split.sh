#!/bin/bash
exec python "$(dirname -- "${BASH_SOURCE[0]}")/scene.py" "$@"
