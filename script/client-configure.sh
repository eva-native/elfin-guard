#!/bin/bash

PROGRAM=${0##*/}
VERSION="0.0.1a"
VERBOSE=":"

function abort {
  printf "%s\n" "$1" >&2
  exit 1
}

function verbose {
  printf "%s\n" "$1" >&2
}

PRIVATE_KEY="$(wg genkey)"
PUBLIC_KEY="$(echo $PRIVATE_KEY | wg pubkey)"

function usage {
  cat <<-EoN
usage $PROGRAM -hvV [OUTPUT_DIR] [SERVER_PUBLIC_KEY] [ENDPOINT] [IPv4] ([IPv6])
  --comment   -c  Set comment
  --help      -h  Print this message
  --verbose   -v  Verbose output (Default: off)
  --version   -V  Display version ($VERSION)
EoN
}

while getopts ":c:hvV" OPT ; do
  case $OPT in
    c ) COMMENT="$OPTARG" ;;
    h ) usage ; exit 0 ;;
    v ) VERBOSE="verbose" ;;
    V ) echo "$VERSION" && exit 0 ;;
    - )
      case $OPTARG in
        comment=* ) COMMENT="${OPTARG#*=}" ;;
        comment   )
          COMMENT="${!OPTIND}"
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

if (( $# < 4 )) || (( $# > 5 )) ; then
  abort "error: incorrect number of parameters"
fi

OUTPUT_DIR="$1"
SERVER_PUBLIC_KEY="$2"
ENDPOINT="$3"
IPv4="$4"
IPv6="$5"

if [[ ! -d "$OUTPUT_DIR" ]] ; then
  $VERBOSE "warn: $OUTPUT_DIR does not exist"
  mkdir -p "$OUTPUT_DIR" || abort "error: not enough permissions"
fi

touch "$OUTPUT_DIR/key" 2>/dev/null || abort "error: not enough permissions"
touch "$OUTPUT_DIR/key.pub" 2>/dev/null || abort "error: not enough permissions"

echo "$PRIVATE_KEY" > "$OUTPUT_DIR/key" && \
$VERBOSE "info: write private key to $OUTPUT_DIR/key"

echo "$PUBLIC_KEY" > "$OUTPUT_DIR/key.pub" && \
$VERBOSE "info: write public key to $OUTPUT_DIR/key.pub"

chmod go= "$OUTPUT_DIR/key"

[[ $COMMENT ]] && CONTENT+="# $COMMENT"$'\n'

CONTENT+="[Interface]"$'\n'
CONTENT+="PrivateKey=$PRIVATE_KEY"$'\n'
CONTENT+="Address=$IPv4"$'\n'

if [[ $IPv6 ]] ; then
  $VERBOSE "info: added ipv6 to peer config $IPv6"
  CONTENT+="Address=$IPv6"$'\n'
fi

CONTENT+="[Peer]"$'\n'
CONTENT+="PublicKey=$SERVER_PUBLIC_KEY"$'\n'
CONTENT+="AllowedIPs=0.0.0.0/0, ::/0"$'\n'
CONTENT+="Endpoint=$ENDPOINT"

echo "$CONTENT" > "$OUTPUT_DIR/wg0.conf"
