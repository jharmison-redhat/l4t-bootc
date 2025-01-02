#!/bin/bash

set -e

echo -n Waiting for Jetson in recovery mode to be plugged in
while ! lsusb -d 0955:7023 >/dev/null 2>&1; do
    echo -n .
    sleep 1
done
echo

cd "$(dirname "$(realpath "$0")")/../tmp/Linux_for_Tegra"

source ../.venv/bin/activate
sudo -E env PATH="$PATH" ./flash.sh jetson-agx-orin-devkit external
