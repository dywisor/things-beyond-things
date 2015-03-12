#!/bin/sh
# Usage: system_install.sh [-p|--pretend] <srcroot> <dstroot> [<force_owner> [<root>]]
#
set -u
exec 0</dev/null
umask 0022

FAKE_MODE=n
case "${1-}" in
   '-p'|'--pretend') FAKE_MODE=y; shift || exit ;;
esac

case "${1-}" in
   '-h'|'--help') exit 0 ;;
esac

MODE=system
: ${DEREF_UNKNOWN_AS_ROOT:=y}
SRCROOT="${1:?missing <srcroot> arg.}"
DSTROOT="${2:?missing <dstroot> arg.}"
DSTROOT_ETC="${DSTROOT%/}/etc"
[ -d "${DSTROOT}" ] || exit

target_owner="${3:--}"
[ "${target_owner}" != "-" ] || target_owner="0:0"

ROOT="${4-${ROOT:-${DSTROOT}}}"

set --

. "${TBT_PRJROOT:-${SRCROOT}}/functions.sh" || exit 8
[ -d "${DSTROOT_ETC}" ] || target_dodir "${DSTROOT_ETC}"

## copy config
S="${SRCROOT}/sysfiles"
D="${DSTROOT_ETC}"
if [ -d "${S}" ]; then
   target_copytree "${SRCROOT}/sysfiles" "${DSTROOT_ETC}"

   if [ -f "${SRCROOT}/postcopy.sh" ]; then
      . "${SRCROOT}/postcopy.sh" || die "Failed to run postcopy.sh!"
   fi
fi


## apply permissions read from permtab
apply_permtab "${DSTROOT}" "${DSTROOT_ETC}" "${SRCROOT}/permtab.system"
