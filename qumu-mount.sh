#!/bin/bash
set -euo pipefail

THIS_SCRIPT="$0"
DEFAULT_MOUNTPOINT="$(dirname $0)/mountpoint"

function errcho {
        echo "$@" >&2
}

function fail {
        if [[ $# -gt 0 ]]; then
                errcho "$@"
        fi
        exit 1
}

function usage_error {
        if [[ $# -gt 0 ]]; then
                errcho "$@"
                errcho
        fi
        errcho "Usage: ${THIS_SCRIPT} [OPTIONS] QCOW2_FILE"
        errcho
        errcho "Options:"
        errcho "  -n, --nbd NBD_INDEX      index of the net block device to use"
        errcho "  -t, --target MOUNTPOINT  path to target mountmoint"
        errcho "  -p, --part PART_INDEX    index of partition to be mounted"
        fail
}

function check_parameter { #arg1: param descr
        #...args: remaining script parameters
        if [[ $# -lt 3 ]]; then
                usage_error "Expecting $1 as $2 parameter, got nothing"
        elif [[ $# =~ ^- ]]; then
                fail "Expecting $1 as $2 parameter, got '$3'"
        fi
}

function check_parameter_decint { #arg1: param descr
        #...args: remaining script parameters
        check_parameter "$@"
        if [[ ! "$3" =~ ^[[:digit:]]+$ ]]; then
                fail "Expecting $1 as $2 parameter to be decimal integer, got '$3'"
        fi
        local n=$(("$3"))
        if [[ "$3" != "$n" ]]; then
                fail "Expecting $1 as $2 parameter to be decimal integer, got '$3'"
        fi
}

if [[ $# -eq 0 ]]; then
        usage_error
fi

NBD_INDEX=0
MOUNTPOINT="$DEFAULT_MOUNTPOINT"
PART_INDEX=1

# load nbd kernel module if /dev/nbd0 is not available
if [[ ! -b /dev/nbd0 ]]; then
        modprobe nbd
fi

while [[ $# -gt 1 ]]; do
        case "$1" in
        '--nbd' | '-n')
                check_parameter_decint 'net block device index' "$@"
                shift
                NBD_INDEX=$(("$1"))
                shift
                ;;
        '--target' | '-t')
                check_parameter 'mounting point' "$@"
                shift
                MOUNTPOINT="$1"
                shift
                ;;
        '--part' | '-p')
                check_parameter_decint 'partition index' "$@"
                shift
                PART_INDEX=$(("$1"))
                shift
                ;;
        *)
                usage_error "Invalid option '$1'"
                ;;
        esac
done

if [[ $# -eq 0 ]]; then
        usage_error 'Missing compulsory argument <path_to_qcow2>'
fi
QCOW_PATH="$1"
if [[ ! -f "$QCOW_PATH" ]]; then
        fail "No such qcow2 file '$QCOW_PATH'"
fi

NBD_DEV="/dev/nbd${NBD_INDEX}"
if [[ ! -b "$NBD_DEV" ]]; then
        fail "No such nbd device '$NBD_DEV'"
fi

if [[ ! -d "$MOUNTPOINT" ]]; then
        fail "Mountpoint '$MOUNTPOINT' is not a directory"
fi

echo "Mounting '$QCOW_PATH' as $NBD_DEV."
qemu-nbd --connect "$NBD_DEV" "$QCOW_PATH"

PART_PATH="${NBD_DEV}p${PART_INDEX}"
if [[ ! -b "$PART_PATH" ]]; then
        errcho "No such partition ${PART_PATH}"
        echo "Unmounting ${NBD_DEV}."
        qemu-nbd --disconnect "${NBD_DEV}"
        fail
fi

echo "Mounting ${PART_PATH} to '${MOUNTPOINT}'."
mount "${PART_PATH}" "${MOUNTPOINT}"
