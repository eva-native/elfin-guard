#!/bin/bash

PROGRAM="${0##*/}"
VERSION="0.0.1b"
VERBOSE=":"

function warn {
  printf "%s\n" "$1" >&2
}

function abort {
  warn "$1"
  exit 1
}

function make_ipv6 {
  if [[ -f /etc/machine-id ]] ; then
    local hash="$(printf "$(date +%s%N)$(</etc/machine-id)" | sha1sum | cut -c 31-40)"
    echo "fd${hash:0:2}:${hash:2:4}:${hash:6:4}::1/64"
    exit
  fi
  echo "warning: can't gnerate IPv6." >&2
  echo "-"
}

PRIVATE_KEY="$(wg genkey)"
PUBLIC_KEY="$(echo $PRIVATE_KEY | wg pubkey)"

PORT="55555"
IPv4="172.16.0.1/12"
IPv6="$(make_ipv6)"
MTU="1500"
INTERFACE="$(ip route show default | awk '{ print $5 }')"
KEY_NAME="server"
CONF_NAME="wg0.conf"
OUTPUT_DIR="/etc/wireguard"

function usage {
  cat <<-EoN
usage $PROGRAM (-p [PORT]|-4 [IPv4]|-6 [IPv6]|-o [DIR]|-m [MTU])
  --port      -p  Define port (Default: $PORT)
  --ipv4      -4  Define IPv4 (Default: $IPv4)
  --ipv6      -6  Define IPv6 (Default: $IPv6)
  --mtu       -m  Define MTU (Default: $MTU)
  --interface -i  Define interface (Default: $INTERFACE)
  --key       -k  Define file name (Default: $KEY_NAME)
  --conf      -c  Define output config name (Default: $CONF_NAME)
  --output    -o  Define output directory (Default: $OUTPUT_DIR)
  --verbose   -v  Verbose output (Default: off)
  --version   -V  Display version ($VERSION)
  --help      -h  Print this message
EoN
}

while getopts ":-:p:4:6:i:k:c:o:hvV" OPT ; do
  case $OPT in
    p ) PORT="$OPTARG" ;;
    4 ) IPv4="$OPTARG" ;;
    6 ) IPv6="$OPTARG" ;;
    m ) MTU="$OPTARG" ;;
    i ) INTERFACE="$OPTARG" ;;
    k ) KEY_NAME="$OPTARG" ;;
    c ) CONF_NAME="$OPTARG" ;;
    o ) OUTPUT_DIR="$OPTARG" ;;
    h ) usage ; exit 0 ;;
    v ) VERBOSE="echo" ;;
    V ) echo "$VERSION" && exit 0 ;;
    - )
      case $OPTARG in
        port=* ) PORT="${OPTARG#*=}" ;;
        port   )
          PORT="${!OPTIND}"
          let OPTIND++
        ;;

        ipv4=* ) IPv4="${OPTARG#*=}" ;;
        ipv4   )
          IPv4="${!OPTIND}"
          let OPTIND++
        ;;

        ipv6=* ) IPv6="${OPTARG#*=}" ;;
        ipv6   )
          IPv6="${!OPTIND}"
          let OPTIND++
        ;;

        mtu=* ) MTU="${OPTARG#*=}" ;;
        mtu   )
          MTU="${!OPTIND}"
          let OPTIND++
        ;;

        interface=* ) INTERFACE="${OPTARG#*=}" ;;
        interface   )
          INTERFACE="${!OPTIND}"
          let OPTIND++
        ;;

        key=* ) KEY_NAME="${OPTARG#*=}" ;;
        key   )
          KEY_NAME="${!OPTIND}"
          let OPTIND++
        ;;

        conf=* ) CONF_NAME="${OPTARG#*=}" ;;
        conf   )
          CONF_NAME="${!OPTIND}"
          let OPTIND++
        ;;

        output=* ) OUTPUT_DIR="${OPTARG#*=}" ;;
        output   )
          OUTPUT_DIR="${!OPTIND}"
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

[[ -a "$OUTPUT_DIR" ]] || abort "error: $OUTPUT_DIR does not exists"
[[ -d "$OUTPUT_DIR" ]] || abort "error: $OUTPUT_DIR is not a directory"

touch "$OUTPUT_DIR/$KEY_NAME" 2>/dev/null || abort "error: not enough permissions"
touch "$OUTPUT_DIR/$KEY_NAME.pub" 2>/dev/null || abort "error: not enough permissions"

echo "$PRIVATE_KEY" > "$OUTPUT_DIR/$KEY_NAME"
$VERBOSE "info: private key writen to $OUTPUT_DIR/$KEY_NAME"
echo "$PUBLIC_KEY" > "$OUTPUT_DIR/$KEY_NAME.pub"
$VERBOSE "info: public key writen to $OUTPUT_DIR/$KEY_NAME.pub"

chmod go= "$OUTPUT_DIR/$KEY_NAME"

# This is simple solution but not perfect

if [[ "$(</proc/sys/net/ipv4/ip_forward)" = "0" ]] ; then
  echo "net.ipv4.ip_forward = 1" 2>/dev/null >> /etc/sysctl.conf
  [[ $? ]] && echo "warning: can't enable IPv4 forwarding" >&2
fi

$VERBOSE "info: ipv4 forwarding enabled"

if [[ $IPv6 ]] && [[ "$(</proc/sys/net/ipv6/conf/all/forwarding)" = "0" ]] ; then
  echo "net.ipv6.conf.all.forwarding = 1" 2>/dev/null >> /etc/sysctl.conf
  [[ $? ]] && echo "warning: can't enable IPv6 forwarding" >&2
fi

$VERBOSE "info: ipv6 forwarding enabled"

if [[ $(ufw allow $PORT/udp) ]] ; then
  $VERBOSE "info: ufw allow $PORT/udp"
  $VERBOSE "info: pls restart firewall"
else
  warn "warn: 'ufw allow $PORT/udp' failed, open port manualy"
fi

CONTENT+="[Interface]"$'\n'
CONTENT+="PrivateKey=$PRIVATE_KEY"$'\n'
CONTENT+="Address=$IPv4"$([[ $IPv6 ]] && echo ", $IPv6")$'\n'
CONTENT+="ListenPort=$PORT"$'\n'
CONTENT+="SaveConfig=true"$'\n'

CONTENT+="PostUp=ufw route allow in on ${CONF_NAME%.*} out on $INTERFACE"$'\n'
CONTENT+="PostUp=iptables -t nat -I POSTROUTING -o $INTERFACE -j MASQUERADE"$'\n'

CONTENT+="PreDown=ufw route delete allow in on ${CONF_NAME%.*} out on $INTERFACE"$'\n'
CONTENT+="PreDown=iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE"$'\n'

if [[ $IPv6 ]] ; then
  CONTENT+="PostUp=ip6tables -t nat -I POSTROUTING -o $INTERFACE -j MASQUERADE"$'\n'
  CONTENT+="PreDown=ip6tables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE"$'\n'
fi

$VERBOSE "info: config:"
$VERBOSE "$CONTENT"
echo "$CONTENT" > "${OUTPUT_DIR}/${CONF_NAME}"
