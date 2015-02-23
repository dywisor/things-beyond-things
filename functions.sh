#!/bin/sh

## @noreturn die ( message:="died.", exit_code:=250 )
##
##  Prints an error message to stderr and exits.
##
die() {
   printf '%s\n' "${1:+died: }${1:-died.}" 1>&2
   exit ${2:-250}
}

## int __cmd__ ( *cmdv )
## @nostdout @nostderr int __qcmd__ ( *cmdv )
## void autodie ( *cmdv )
##
##  Command wrappers.
##
##  These functions simply print the command to stdout if
##  FAKE_MODE is set to 'y' (when including this file!).
##
if [ "${FAKE_MODE:-X}" = "y" ]; then

__cmd__()  { printf '%s\n' "${*}"; }
__qcmd__() { printf '%s\n' "${*}"; }
autodie()  { printf '%s\n' "${*}"; }

else
__cmd__()  { "${@}"; }
__qcmd__() { "${@}" 1>/dev/null 2>&1; }
autodie()  { "${@}" || die "command '${*}' returned ${?}." ${?}; }
fi

## @autodie target_chown ( fspath, **target_owner )
##
##  Changes the owner of %fspath to %target_owner.
##
##  Ignores symlinks.
##
target_chown() {
   : ${1:?}
   [ ! -h "${1}" ] || return 0
   autodie chown -- "${target_owner:?}" "${1}"
}

## @autodie do_chown_chmod ( owner:="-", mode:="-", fspath )
##
##  Changes the owner of %fspath to %owner (if != "-") and then
##  its mode to %mode (if != "-").
##
##  Ignores symlinks.
##
do_chown_chmod() {
   [ ! -h "${3:?}" ] || return 0
   [ "${1:--}" = "-" ] || autodie chown -- "${1}" "${3:?}"
   [ "${2:--}" = "-" ] || autodie chmod -- "${2}" "${3:?}"
}

## @autodie target_chown_chmod ( mode:="-", fspath )
target_chown_chmod() {
   do_chown_chmod "${target_owner:?}" "${@}"
}

## @autodie target_dodir ( fspath, [mode] )
target_dodir() {
   : ${1:?}
   if [ -h "${1}" ]; then
      return 0
   elif [ -d "${1}" ]; then
      [ -z "${2-}" ] || autodie chmod -- "${2}" "${1}"
   else
      autodie mkdir -p -m 0755 -- "${1}"
      target_chown_chmod "${2:-0755}" "${1}"
   fi
}

## @autodie target_rmfile ( fspath )
target_rmfile() {
   : ${1:?}
   if [ -h "${1}" ] || [ -f "${1}" ]; then
      autodie rm -- "${1}"
   elif [ -d "${1}" ]; then
      die "not a file: ${1}"
   fi
}

## @autodie target_copyfile ( src, dst )
target_copyfile() {
   : ${1:?} ${2:?}
   target_rmfile "${2}"
   autodie cp -dp -- "${1}" "${2}"
   target_chown "${2}"
}

## @private int target_copytree__filter ( name )
##
##  Returns 0 if target_copytree__inner() should not copy the given name
##  to the dstdir, else 1.
##
##  Dies if the the filename/dirname delimiter is encountered.
##
target_copytree__filter() {
   case "${1}" in
      '///')
         die "logically broken."
      ;;
      '.'|'..')
         return 0
      ;;
   esac

   return 1
}

## @private @autodie target_copytree__inner (
##    src, dst, srcroot_relpath, **target_owner
## )
##
##  Recursively copies %src to %dst.
##  %srcroot_relpath must be the path of %src relative to the src root
##  (which is what you pass to target_copytree()).
##
##  Do not call this function directly, use target_copytree().
##
target_copytree__inner() {
   local src_dir
   local dst_dir
   local srcroot_relpath
   local iter
   local name

   src_dir="${1:?}"
   dst_dir="${2:?}"
   srcroot_relpath="${3:?}"

   # collect files and dirs and add their names to @argv
   # * set @argv := filename/dirname delimiter
   # * add file names to left (<filename> "$@")
   # * append dir names to the right ("$@" <dirname>)
   #
   #  This breaks (local-dependent) ordering, but that doesn't matter here.
   #
   set -- ///

   for iter in "${src_dir}/"* "${src_dir}/."*; do
      name="${iter##*/}"

      if target_copytree__filter "${name}"; then
         :

      elif [ -h "${iter}" ]; then
         die "srcdir must not contain symlinks: ${src_dir}"
         #set -- "${name}" "${@}"

      elif [ -d "${iter}" ]; then
         set -- "${@}" "${name}"

      elif [ -e "${iter}" ]; then
         set -- "${name}" "${@}"
      fi
   done

   if [ ${#} -gt 1 ]; then
      # %iter := mode of %src_dir
      iter="$(stat -c '%a' "${src_dir}")" && \
         [ -n "${iter}" ] || die "Failed to stat ${src_dir}."

      target_dodir "${dst_dir}" "${iter}"
   fi

   # process file names
   while [ ${#} -gt 0 ]; do
      name="${1}"
      [ "${name}" != "///" ] || { shift; break; }

      target_copyfile "${src_dir}/${name}" "${dst_dir}/${name}"
      shift
   done

   # (recursively) process dirs
   while [ ${#} -gt 0 ]; do
      name="${1}"

      target_copytree__inner \
         "${src_dir}/${name}" "${dst_dir}/${name}" \
         "${srcroot_relpath%/}/${name}"
      shift
   done
}

## @autodie target_copytree ( src, dst, **target_owner )
##
##  Recursively copies files from %src to %dst and sets the owner to
##  %target_owner.
##
target_copytree() {
   target_copytree__inner "${1:?}" "${2:?}" "/"
}

## @stdout _read_passwd_or_group ( file, name )
##
##  Reads a passwd/group file and prints the first 4 fields.
##
_read_passwd_or_group() {
   awk -F : -v "name=${2}" \
      '($1 == name) { print $1, $2, $3, $4; exit; }' "${1}"
}

test_is_int() {
   { test "${1:-X}" -eq 0 || test "${1:-X}" -ne 0; } 2>/dev/null
}

## int _permtab_deref_file_owner ( file_owner, **ROOT, **file_owner! )
##
##  Determines the numeric owner (uid/gid) of %file_owner.
##
##  Returns 0 if %file_owner was or has been set to a numeric owner,
##  else non-zero.
##
_permtab_deref_file_owner() {
   ##file_owner="${1}"
   case "${1}" in
      ''|'-')
         file_owner=
         return 0
      ;;

      '@')
         if [ "${MODE:?}" = "system" ]; then
            file_owner=
         else
            file_owner="${target_owner:?}"
         fi
         # %target_owner is numeric by assumption.
         return 0
      ;;

      '+')
         # %target_owner is numeric by assumption.
         file_owner="${target_owner:?}"
         return 0
      ;;
   esac

   if [ "${ROOT?}" = "/" ]; then
      # leave it up to chown
      return 0
   fi

   local user
   local group
   local uid
   local gid
   local cache_key                                ### FEATURE_CACHE
   local cached_val                               ### FEATURE_CACHE

   uid=; gid=;
   case "${1}" in
      *:*) user="${1%%:*}";  group="${1#*:}" ;;
      *.*) user="${1%%.*}";  group="${1#*.}" ;;
      *)   user="${1}"; group= ;;
   esac

   ! test_is_int "${user:?}"  || uid="${user}"
   ! test_is_int "${group:?}" || gid="${group}"

   if [ -n "${uid}" ] && [ -n "${gid}" ]; then
      # numeric owner
      file_owner="${uid}:${gid}"
      return 0
   fi

   if [ -z "${ROOT}" ]; then
      # cannot deref
      return 222
   fi

   cache_key="__file_owner_${user}___${group}"    ### FEATURE_CACHE
   eval "cached_val=\"\${${cache_key}-}\""        ### FEATURE_CACHE
   if [ -n "${cached_val}" ]; then                ### FEATURE_CACHE
      file_owner="${cached_val}"                  ### FEATURE_CACHE
      return 0                                    ### FEATURE_CACHE
   fi                                             ### FEATURE_CACHE



   if [ -z "${uid}" ] && [ -f "${ROOT%/}/etc/passwd" ]; then
      set -- $( _read_passwd_or_group "${ROOT%/}/etc/passwd" "${user}") || :

      uid="${3-}"
      [ -n "${group}" ] || gid="${4-}"
   fi

   if [ -z "${gid}" ]; then
      if [ -z "${group}" ]; then
         # -z group && -n uid ==> fail -- dont mix names and numbers
         return 222

      elif [ -f "${ROOT%/}/etc/group" ]; then
         set -- $( _read_passwd_or_group "${ROOT%/}/etc/group" "${group}") || :
         gid="${3-}"
      fi
   fi

   if [ "${DEREF_FAIL_TO_ROOT:-n}" ]; then
      : ${uid:=0}
      : ${gid:=0}

   elif [ -z "${uid}" ]; then
      return 190

   elif [ -z "${gid}" ]; then
      return 191
   fi

   file_owner="${uid}:${gid}"
   eval "${cache_key}=\"${file_owner}\""          ### FEATURE_CACHE
}

## iter_permtab ( abspath_root, relpath_root, infile, function, *args )
##
##  Reads a permtab file if exists and calls
##   %function (
##      *args,
##      **file_type, **file_mode, **file_owner, **file_path, **file_path_abs
##  )
##   for each entry.
##
##
iter_permtab() {
   : ${MODE:?}
   local infile
   local lino
   local iter_permtab_abspath_root
   local iter_permtab_relpath_root

   local file_type
   local file_mode
   local file_owner
   local file_path
   local file_path_abs

   iter_permtab_abspath_root="${1:?}"
   iter_permtab_relpath_root="${2:?}"
   infile="${3:?}"

   shift 3 && [ ${#} -gt 0 ] && [ -n "${1}" ] || \
      die "iter_permtab(): missing <function> arg."

   [ -s "${infile}" ] || return 0

   lino=0
   while read -r file_type file_mode file_owner file_path; do
      lino=$(( ${lino} + 1 )) || :
      file_path_abs=

      case "${file_type}" in
         ''|'#'*)
            continue
         ;;
      esac

      if \
         [ -z "${file_mode}"  ] || \
         [ -z "${file_owner}" ] || \
         [ -z "${file_path}"  ]
      then
         die "permtab-install: ${infile}: ${lino}: missing mode, owner or filepath."
      fi

      case "${file_mode}" in
         '-'|'_'|'@') file_mode= ;;
      esac

      _permtab_deref_file_owner "${file_owner}" || \
         die "failed to determine file owner '${file_owner:-???}' (${?})"

      case "${file_path}" in
         */|.|..|./*|../*|*/./*|*/../*|*/.|*/..)
            die "permtab-install: invalid filepath: ${file_path}"
         ;;
         /*)
            file_path_abs="${iter_permtab_abspath_root%/}${file_path}"
         ;;
         *)
            file_path_abs="${iter_permtab_relpath_root%/}/${file_path}"
         ;;
      esac

      "${@}" || return ${?}
   done < "${infile}" || die "Failed to read permtab '${infile}'"
}

## @autodie _do_apply_permtab (...)
##
##  Default permtab entry handler, used by apply_permtab().
##
_do_apply_permtab() {
   case "${file_type}" in
      [fFdD]'?')
         # bogus: F?, D? := "create if exists"
         [ -e "${file_path_abs}" ] || \
         [ -h "${file_path_abs}" ] || return 0

         file_type="${file_type%\?}"
      ;;

      ?*'_')
         file_type="${file_type%_}"
      ;;
   esac

   case "${file_type}" in
      'f')
         autodie test -f "${file_path_abs}"
      ;;
      'd')
         autodie test -d "${file_path_abs}"
      ;;
      'F')
         if [ ! -f "${file_path_abs}" ]; then
            if [ -e "${file_path_abs}" ] || [ -h "${file_path_abs}" ]; then
               die "permtab-install: ${file_path_abs} exists (F)"
            fi
            autodie touch "${file_path_abs}"
            : ${file_owner:=${target_owner}}
         fi
      ;;
      'D')
         if [ ! -d "${file_path_abs}" ]; then
            if [ -e "${file_path_abs}" ] || [ -h "${file_path_abs}" ]; then
               die "permtab-install: ${file_path_abs} exists (D)"
            fi
            autodie mkdir -m "${file_mode}" -- "${file_path_abs}"
            : ${file_owner:=${target_owner}}
         fi
      ;;
      *)
         die "permtab-install: invalid file_type: ${file_type}"
      ;;
   esac

   do_chown_chmod "${file_owner}" "${file_mode}" "${file_path_abs}"
}

## apply_permtab ( abspath_root, relpath_root, infile )
apply_permtab() {
   iter_permtab "${1:?}" "${2:?}" "${3:?}" _do_apply_permtab
}
