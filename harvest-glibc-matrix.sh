#!/bin/bash
# Harvest glibc / libstdc++ / libc facts from real distribution images.
#
# Why this exists: the compatibility matrix on the site cannot be written from
# memory - each row has to be measured inside the actual image. This script pulls
# one image at a time, probes it, records one JSON line, then removes the image so
# disk usage stays flat.
#
# Output: ./out/rows.jsonl (one JSON object per image), ./out/progress.log
#         override the directory with OUT_DIR=/some/path
#
# Usage: harvest-glibc-matrix.sh [image ...]     (no args = built-in list)
set -uo pipefail

OUT=${OUT_DIR:-./out}
ROWS=$OUT/rows.jsonl
LOG=$OUT/progress.log
mkdir -p "$OUT"
: > "$ROWS"

IMAGES_DEFAULT=(
  "ubuntu:16.04" "ubuntu:18.04" "ubuntu:20.04" "ubuntu:22.04" "ubuntu:24.04" "ubuntu:25.04"
  "debian:9" "debian:10" "debian:11" "debian:12" "debian:13"
  "alpine:3.16" "alpine:3.18" "alpine:3.20" "alpine:3.22"
  "centos:7"
  "rockylinux:8" "rockylinux:9"
  "almalinux:8" "almalinux:9"
  "fedora:40" "fedora:41" "fedora:42"
  "amazonlinux:2" "amazonlinux:2023"
  "archlinux:latest"
  "opensuse/leap:15.6"
)

PROBE='
set +e
. /etc/os-release 2>/dev/null
DISTRO_NAME="${PRETTY_NAME:-unknown}"
DISTRO_ID="${ID:-}"
DISTRO_VER="${VERSION_ID:-}"
# glibc: `ldd --version` prints a clean trailing version, while running libc.so.6
# directly ends the first line with a period - prefer ldd, fall back to libc.
GLIBC=$(ldd --version 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+$")
if [ -z "$GLIBC" ]; then
  for p in /lib/x86_64-linux-gnu/libc.so.6 /lib64/libc.so.6 /usr/lib/libc.so.6 /usr/lib64/libc.so.6; do
    [ -e "$p" ] || continue
    GLIBC=$("$p" 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+" | tail -1)
    [ -n "$GLIBC" ] && break
  done
fi
# musl: the loader prints the version on the second line
MUSL=""
for p in /lib/ld-musl-x86_64.so.1 /lib/libc.musl-x86_64.so.1; do
  [ -e "$p" ] || continue
  MUSL=$("$p" --version 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
  [ -n "$MUSL" ] && break
done
# libstdc++: highest GLIBCXX symbol version embedded in the library (grep -a so it
# works on images without binutils/strings)
CXX=""
for p in /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib64/libstdc++.so.6 /usr/lib/libstdc++.so.6; do
  [ -e "$p" ] || continue
  CXX=$(grep -aoE "GLIBCXX_3\.[0-9]+(\.[0-9]+)?" "$p" 2>/dev/null | sort -V | tail -1)
  [ -n "$CXX" ] && break
done
PKG=$(command -v apt-get >/dev/null && echo apt || (command -v dnf >/dev/null && echo dnf || (command -v yum >/dev/null && echo yum || (command -v apk >/dev/null && echo apk || echo unknown))))
printf "%s|%s|%s|%s|%s|%s|%s\n" "$DISTRO_NAME" "$DISTRO_ID" "$DISTRO_VER" "${GLIBC:-}" "${MUSL:-}" "${CXX:-}" "$PKG"
'

IMAGES=("$@")
[ ${#IMAGES[@]} -eq 0 ] && IMAGES=("${IMAGES_DEFAULT[@]}")

total=${#IMAGES[@]}
i=0
for img in "${IMAGES[@]}"; do
  i=$((i + 1))
  printf "[%d/%d] %s ... " "$i" "$total" "$img" | tee -a "$LOG"
  if ! timeout 180 docker pull -q --platform linux/amd64 "$img" >/dev/null 2>&1; then
    echo "PULL-FAILED" | tee -a "$LOG"
    printf '{"image":"%s","error":"pull-failed"}\n' "$img" >> "$ROWS"
    continue
  fi
  raw=$(timeout 90 docker run --rm --platform linux/amd64 --entrypoint sh "$img" -c "$PROBE" 2>/dev/null | tail -1)
  if [ -z "$raw" ]; then
    echo "PROBE-FAILED (no shell or no output)" | tee -a "$LOG"
    printf '{"image":"%s","error":"probe-failed"}\n' "$img" >> "$ROWS"
  else
    IFS='|' read -r dname did dver glibc musl cxx pkg <<< "$raw"
    printf '{"image":"%s","distro":"%s","id":"%s","version":"%s","glibc":"%s","musl":"%s","libstdcxx_max":"%s","pkg":"%s"}\n' \
      "$img" "${dname//\"/}" "$did" "$dver" "$glibc" "$musl" "$cxx" "$pkg" >> "$ROWS"
    echo "OK glibc=${glibc:-none} musl=${musl:-none} cxx=${cxx:-none}" | tee -a "$LOG"
  fi
  docker rmi -f "$img" >/dev/null 2>&1 || true
done

echo "done: $(wc -l < "$ROWS") rows in $ROWS"
