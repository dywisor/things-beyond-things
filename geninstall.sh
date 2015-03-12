#!/bin/sh
# Usage: geninstall.sh [<srcroot> [<tbt_prjroot>]]
#
set -u
exec 0</dev/null

deref_relpath() {
   v0=
   case "${1}" in
      '')
         printf "Failed to deref ${2:-relpath}: <empty>" 1>&2
         return 2
      ;;
      /*)
         v0="${1}"
      ;;
      *)
         v0="$(readlink -f "${1}")"
         if [ -z "${v0}" ]; then
            printf '%s\n' "Failed to deref ${2:-relpath}: ${1}" 1>&2
            return 1
         fi
      ;;
   esac
}

if [ -n "${1-}" ]; then
   deref_relpath "${1:?<srcroot>}" "srcroot" || exit 9
   SRCROOT="${v0}"
else
   SRCROOT=
fi

deref_relpath "${2-${TBT_PRJROOT-${PWD}}}" "tbt prjroot" || exit 9
TBT_PRJROOT="${v0}"

if \
   [ ! -f "${TBT_PRJROOT}/system_install.sh" ] || \
   [ ! -f "${TBT_PRJROOT}/user_install.sh" ]
then
   printf '%s\n' "Bad tbt prjroot: ${TBT_PRJROOT:-<empty>}" 1>&2
   exit 9
fi



cat << EOF
S     := ${SRCROOT:-\$(CURDIR)}
TBT   := ${TBT_PRJROOT}
SHELL ?= /bin/sh

ifeq (\$(D),)
\$(error D is not set)
endif

ifneq (\$(PRETEND),)
INSTALL_OPTS += -p
endif

PHONY += default
default:
	false

PHONY += \$(addprefix install-,user system)
install-user install-system: install-%:
	TBT_PRJROOT="\$(TBT)" \\
	ROOT="\$(ROOT)" \\
	DEREF_UNKNOWN_AS_ROOT="\$(DEREF_UNKNOWN_AS_ROOT)" \\
	\$(SHELL) "\$(TBT)/\$(*)_install.sh" \$(INSTALL_OPTS) \\
		"\$(S)" "\$(D)" \$(INSTALL_ARGS)

.PHONY: \$(PHONY)
EOF
