#!/bin/sh
# Usage: user_install.sh [-p|--pretend] <srcroot> <dstroot> [<owner> [<root>]]
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

MODE=user
: ${DEREF_UNKNOWN_AS_ROOT:=n}
SRCROOT="${1:?missing <srcroot> arg.}"
DSTHOME="${2:?missing <dstroot> arg.}"
DSTCFGDIR="${DSTHOME}/.config"
[ -d "${DSTHOME}" ] || exit

if [ "${3:--}" = "-" ]; then
   set -- $(stat -c '%u %g'  "${DSTHOME}/.") || exit 20
   _target_uid="${1:?}"
   _target_gid="${2:?}"
   target_owner="${_target_uid}:${_target_gid}"
else
   target_owner="${3}"
fi

: ${ROOT:=${4-}}

set --

. "${TBT_PRJROOT:-${SRCROOT}}/functions.sh" || exit 8


## copy .config to $DSTCFGDIR
S="${SRCROOT}/files"
D="${DSTCFGDIR}"
if [ -d "${S}" ]; then
   target_copytree "${SRCROOT}/files" "${DSTCFGDIR}"

   if [ -f "${SRCROOT}/postcopy.sh" ]; then
      . "${SRCROOT}/postcopy.sh" || die "Failed to run postcopy.sh!"
   fi
fi

## install dotfiles in $DSTHOME
target_dodir "${DSTCFGDIR}"
autodie touch "${DSTCFGDIR}/.keep"

if __qcmd__ ln -- \
   "${DSTCFGDIR}/.keep" "${DSTHOME}/.dotconfig_hardlink_check.$$"
then
autodie rm -- "${DSTHOME}/.dotconfig_hardlink_check.$$"

# do_link_dotfile ( src, dst )
do_link_dotfile() { autodie ln -- "${1:?}" "${2:?}"; }

else

# do_link_dotfile ( src, dst )
do_link_dotfile() { target_copyfile "${1:?}" "${2:?}"; }

fi

do_symlink_dotfile() { autodie ln -s -- "${1:?}" "${2:?}"; }


# install_dotfile ( src_name, dst_name )
install_dotfile() {
   : ${1:?} ${2:?}
   autodie test -e "${DSTCFGDIR}/${1}"

   target_rmfile "${DSTHOME}/${2}"
   if [ -d "${DSTCFGDIR}/${1}" ]; then
      do_symlink_dotfile "${DSTCFGDIR}/${1}" "${DSTHOME}/${2}"
   else
      do_link_dotfile "${DSTCFGDIR}/${1}" "${DSTHOME}/${2}"
   fi
}


if [ -s "${SRCROOT}/dotfiles.list" ]; then
   while read -r line; do
      case "${line}" in
         ''|'#'*)
            :
         ;;

         /*|.|..|./*|../*|*/./*|*/../*)
            die "dotfile-install: invalid: ${line}"
         ;;

         *:*|*/)
            die "dotfile-install: not supported: ${line}"
         ;;

         *)
            install_dotfile "${line}" ".${line##*/}"
         ;;
      esac
   done < "${SRCROOT}/dotfiles.list"
fi

## apply permissions read from permtab
apply_permtab "${DSTHOME}" "${DSTCFGDIR}" "${SRCROOT}/permtab"
apply_permtab "${DSTHOME}" "${DSTCFGDIR}" "${SRCROOT}/permtab.user"
