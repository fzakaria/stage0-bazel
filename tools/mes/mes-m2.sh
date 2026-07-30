#!/usr/bin/env bash
set -x

export srcdest=$(realpath $(dirname $(readlink -f $2))/../../../)/
export GUILE_LOAD_PATH=${srcdest}module

executable=$1
shift 2

exec $executable "$@"
