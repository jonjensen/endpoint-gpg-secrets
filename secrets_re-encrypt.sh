#!/bin/sh

# secrets_re-encrypt.sh
# by Kiel Christofferson, 2009
# with contributions by Jon Jensen, David Christensen, Phin Jensen, and others
# Copyright © End Point Corporation
# License: GPLv3+

# I depend upon the existence of a -encrypt.conf file
# available for each secrets file ending in .txt.gpg
# When encrypting a non .txt file, there should be a file
# called ${FILENAME}-encrypt.conf. For example,
# client-secret.pdf would need client-secret.pdf-encrypt.conf
#
# Many compromises were made in an attempt to have this script
# work in MANY shells. Please contribute and keep the following
# things in mind.
#
# Portability notes:
#
# - don't use if ! command;, use command; if [ $? -ne 0 ];
# - don't use [ -e file ] use [ -r file ]
# - don't use $(), use ``
# - don't use ~, use ${HOME}
# - don't use id -u or $UID, use whoami
# - don't use echo -e

# If I live any deeper within the repo than "eprepo/scripts",
# REPO_DIR needs to be changed.

### TRAPS ###
trap 'cleanup 2 "killed by user"' INT
trap 'cleanup 0' EXIT

### VARIABLES ###
# Hardcoded recipients of everything we encrypt
ALWAYS_RECIPIENTS="
BBBF86A5:Jon Jensen
18854430:Josh Williams
24CF4207:Josh Ausborne
"
SELF=`basename $0`
SELF_DIR=`dirname $0`
TXT_EXTN=".txt"
ENC_EXTN=".gpg"
CNF_EXTN="-encrypt.conf"
export TMPDIR=${SELF_DIR}/.tmp
# dirty hack to get to the base repo so that
# .gpg file discovery works
REPO_DIR=`dirname \`cd "${0%/*}" ; pwd -P\``

USAGE="
This script is used for re-encryption of \"secrets\" files.

$0 [-h] [-v] [-d] [-m DIR | -r] [-a | -f FILE1 -f FILE2 ...] [-t PLAIN_FILE1 -t PLAIN_FILE2 ...]
	-a ALL secrets in the repo
	-d output debugging info
	-f specify encrypted file to re-encrypt in bulk fashion (can be used multiple times)
	-h display this help
	-m DIR move unencrypted file to this directory after encrypting
	-r delete unencrypted file after encrypting
	-t specify a plain-text file to encrypt (can be used multiple times)
	-v verbose

If no options are given specifying which files to encrypt:
-t is assumed and all arguments are considered plain-text files to encrypt.
"

### FUNCTIONS ###
isset() {
# test variables
	[ "$1x" != "x" ] && return 0
	return 1
}

cleanup() {
	isset $CLEAN
	if [ $? != 0 ]; then
		isset $FAILED_FILES && echo "A number of files failed to be (re-)encrypted.
This can happen if you don't have permissions to decrypt the file in the first place.
This can happen if you are unable to check the signature of an encrypted file.
This can happen if the plain-text file to start with is named incorrectly.
This can happen if you have not imported the public keys for EVERYONE in the -encrypt.conf.

Failed Files:
$FAILED_FILES"
		#clean temporary files and exit appropriately
		isset $TMPDIR && [ -e $TMPDIR ] && rm -rf $TMPDIR
		isset $2 && echo $2
	fi
	CLEAN="yep"
	exit $1
}

debug() {
	local message
	message="$@"
	isset $DEBUG && echo "---== $message"
	return 0
}

build_gpg_flags() {
	GPG_FLAGS=""
	local conf_file
	local gpgid
	local comment
	conf_file="$1"
	for line in `(echo "$ALWAYS_RECIPIENTS"; cat $conf_file) | grep -v '^#' | tr " " "_"`; do
		gpgid="`echo $line | cut -d':' -f1`"
		comment="`echo $line | cut -d':' -f2`"
		isset $gpgid && GPG_FLAGS="$GPG_FLAGS -r $gpgid"
		isset $comment && GPG_FLAGS="$GPG_FLAGS --comment=\"$comment\""
		debug "GPG_FLAGS now contains: \"$GPG_FLAGS\""
	done
}

reencrypt() {
	local secret
	local crypt_file
	local conf_file
	local plain_file
	local plain_file_base
	isset $TMPDIR && [ -e $TMPDIR ] || mkdir $TMPDIR
	secret=`mktemp -t secret.XXXXXX`
	crypt_file="$1"
	debug "decrypting file to: \"$secret\""
	gpg -q -d $crypt_file 2>/dev/null >$secret || return 1
	debug "decrypted"
	if [ -r $secret ]; then
		debug "plain text file is readable"
		if [ -s "$secret" ]; then
			plain_file=`basename $crypt_file $ENC_EXTN`
			plain_file_base=`basename $plain_file $TXT_EXTN`
			conf_file="`dirname $crypt_file`/${plain_file_base}$CNF_EXTN"
			debug "building gpg flags using conf: $conf_file"
			build_gpg_flags $conf_file || return 1
			debug "running gpg with GPG_FLAGS: \"$GPG_FLAGS\""
			gpg -q -e -s $GPG_FLAGS -o "$crypt_file.new" "$secret"
			[ $? = 0 ] && mv $crypt_file.new $crypt_file || return 1
			debug "moved .new file"
		fi
		rm $secret
	fi
	return 0
}

encrypt() {
	local secret
	local secret_base
	local secret_txt_base
	local crypt_file
	local crypt_tmp
	local conf_file
	isset $TMPDIR && [ -e $TMPDIR ] || mkdir $TMPDIR
	secret="$1"
	secret_base=`basename $secret`
	secret_txt_base=`basename $secret $TXT_EXTN`
	crypt_tmp="$TMPDIR/$secret_base.$ENC_EXTN"
	if [ -r $secret ]; then
		debug "file is readable: $secret"
		if [ -s "$secret" ]; then
			if [ $secret_base != $secret_txt_base ]; then
				secret_base=$secret_txt_base
			fi
			debug "finding matching conf file for secret: $secret"
			conf_file="`find $REPO_DIR -iname \"${secret_base}${CNF_EXTN}\" 2>/dev/null`"
			debug "${secret_base}${CNF_EXTN}"
			isset $conf_file || return 1
			debug "found conf file: $conf_file"
			crypt_file="${secret}${ENC_EXTN}"
			debug "corresponding crypt file: $crypt_file"
			debug "building gpg flags using conf: $conf_file"
			build_gpg_flags $conf_file || return 1
			debug "running gpg on secret: $secret"
			gpg -q -e -s $GPG_FLAGS -o "$crypt_tmp" "$secret"
			if [ $? = 0 ]; then
				mv $crypt_tmp $crypt_file || return 1
				debug "moved tmp file over crypt: $crypt_file"
				isset $MOVE_TO_DIR
				if [ $? = 0 ]; then
					debug "moving $secret to $MOVE_TO_DIR"
					mv $secret $MOVE_TO_DIR
				else
					isset $REMOVE_AFTER && debug "removing $secret" && rm -f $secret
				fi
			fi
		else
			debug "plain text file is empty"
		fi
	else
		debug "$secret not found file or unreadable"
		return 1
	fi
	return 0
}

### PRE REQ ###
for program in basename cat cut dirname find gpg grep mkdir mktemp mv rm sed tr; do
	which $program 2>&1 >/dev/null
	[ $? = 0 ] || cleanup 1 "need \'$program\' in PATH"
done

### COMMAND-LINE PROCESSING ###
if [ -z "$1" ]; then
	echo "$USAGE"
fi

haveopt=
while getopts adf:hm:rt:v option; do
	case "$option" in
		a) haveopt=1; FILES="`find $REPO_DIR -iname "*${ENC_EXTN}"`";;
		d) DEBUG="y";;
		f) haveopt=1; FILES="$FILES $OPTARG";;
		h) echo "$USAGE"; exit;;
		m) MOVE_TO_DIR="$OPTARG";;
		r) REMOVE_AFTER="y";;
		t) haveopt=1; TEXTS="$TEXTS $OPTARG";;
		v) VERBOSE="y";;
		\?) echo "$USAGE" >&2; exit 1;;
	esac
done

# remove options that were processed
for i in `seq 2 $OPTIND`; do
	shift
done
OPTIND=1

# default to -t if no conflicting options given
if [ -z $haveopt ]; then
	TEXTS="$@"
fi

### MAIN ###
isset $FILES && for crypt_file in $FILES; do
	echo "Re-encrypting $crypt_file"
	reencrypt $crypt_file
	[ $? = 0 ] || FAILED_FILES="$FAILED_FILES
$crypt_file" debug "return: $? - added to failed"
done
isset $TEXTS && for text_file in $TEXTS; do
	echo "encrypting $text_file"
	encrypt $text_file
	[ $? = 0 ] || FAILED_FILES="$FAILED_FILES
$text_file" debug "return: $? - added to failed"
done
