#!/bin/bash

PROGRAM=${0##*/}
VERSION="0.0.1a"

PRIVATE_KEY="$(wg genkey)"
PUBLIC_KEY="$(echo $PRIVATE_KEY | wg pubkey)"
