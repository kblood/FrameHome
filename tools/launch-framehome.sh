#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
cd -- "$(dirname -- "$0")"
chmod +x ./FrameHome.arm64
exec ./FrameHome.arm64 "$@"
