#!/bin/sh
# Usage: scripts_install.sh [-p|--pretend] <srcroot> <dstroot> [<force_owner> [<root>]]
#
set -u
exec 0</dev/null
umask 0022

FAKE_MODE=n
case "${1-}" in
   '-p'|'--pretend') FAKE_MODE=y; shift || exit ;;
esac

case "${1-}" in
   '-h'|'--help')
      printf '%s\n' \
         "Usage: scripts_install [-p|--pretend] <srcroot> <dstroot> [<force_owner> [<root>]]"
      exit 0
   ;;
esac

MODE=scripts
: ${DEREF_UNKNOWN_AS_ROOT:=y}
SRCROOT="${1:?missing <srcroot> arg.}"
DSTROOT="${2:?missing <dstroot> arg.}"

target_owner="${3:--}"
[ "${target_owner}" != "-" ] || target_owner="0:0"

ROOT="${4-${ROOT-}}"

set --

. "${TBT_PRJROOT:-${SRCROOT}}/functions.sh" || exit 8
[ -d "${DSTROOT}" ] || target_dodir "${DSTROOT}"


## copy scripts to $DSTROOT
default_file_install scripts "${DSTROOT}"

## apply permissions read from permtab
apply_permtab "${DSTROOT}" "${DSTROOT}" "${SRCROOT}/permtab.scripts"
