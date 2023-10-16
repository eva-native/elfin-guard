#!/bin/bash

PROGRAM=${0##*/}
VERSION="0.0.1a"
VERBOSE=":"

function abort {
  printf "%s\n" "$1" >&2
  exit 1
}

function clean_addr {
  local address="${1##*=}"
  echo "${address%%/*}"
}

function usage {
  cat <<-EoN
usage $PROGRAM (-i[INTERFACE]) [CONF_FILE] [PUBLIC_KEY]
  --interface -i  Set wireguard interface (Default: wg0)
  --verbose   -v  Verbose output (Default: off)
  --version   -V  Display version ($VERSION)
  --help      -h  Print this message
EoN
}

while getopts ":-:i:hvV" OPT ; do
  case $OPT in
    i ) INTERFACE="$OPTARG" ;;
    h ) usage ; exit 0 ;;
    v ) VERBOSE="verbose" ;;
    V ) echo "$VERSION" && exit 0 ;;
    - )
      case $OPTARG in
        interface=* ) INTERFACE="${OPTARG#*=}" ;;
        interface   )
          INTERFACE="${!OPTIND}"
          let OPTIND++
          ;;

        help ) usage ; exit 1 ;;
        verbose ) VERBOSE="echo" ;;
        version ) echo "$VERSION" && exit 0 ;;
        * ) abort "error: unknown option $OPTARG" ;;
      esac
      ;;
    : ) abort "error: no argument supplied" ;;
    * ) abort "error: unknown option $OPTARG" ;;
  esac
done
shift $((OPTIND -1))

(( $# != 2 )) && abort "error: incorrect number of parameters"

INTERFACE="${INTERFACE:-wg0}"
CONF_FILE=$1
PUBLIC_KEY=$2

[[ -a $CONF_FILE ]] || abort "error: file: $CONF_FILE not exists"

while read -r line ; do
  ADDRESSES+="$(clean_addr $line),"
done < <(cat $CONF_FILE|sed -n "/Address=\+/p")

wg set $INTERFACE peer $PUBLIC_KEY allowed-ips ${ADDRESSES%,}
