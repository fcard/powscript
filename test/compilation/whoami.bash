#!/bin/bash

set -e

Compiled="$(cat <(./powscript --compile <(echo "")))"
[[ ! $Compiled =~ "tmp.$(whoami)" ]]

