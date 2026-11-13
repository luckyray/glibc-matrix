# glibc-matrix

Measured glibc and GLIBCXX versions for 27 Linux releases, plus the script that
produced them. Every row comes from running `ldd --version` and reading the highest
`GLIBCXX_*` symbol inside `libstdc++.so.6` **inside the official image** — not from
memory, not from a wiki.

## Why

Two independent version gates decide whether a binary runs:

- `GLIBC_*` symbols come from **libc.so.6**
- `GLIBCXX_*` symbols come from **libstdc++.so.6**

They move independently. Rocky Linux 9 ships glibc 2.34 but only GLIBCXX 3.4.29, so a
C++ binary built on Ubuntu 22.04 (GLIBCXX 3.4.30) satisfies every glibc requirement
and still refuses to start.

## The matrix

| Distribution | Release | glibc | musl | Highest GLIBCXX |
|---|---|---|---|---|
| Ubuntu | 16.04 | 2.23 | — | 3.4.21 |
| Ubuntu | 18.04 | 2.27 | — | 3.4.25 |
| Ubuntu | 20.04 | 2.31 | — | 3.4.28 |
| Ubuntu | 22.04 | 2.35 | — | 3.4.30 |
| Ubuntu | 24.04 | 2.39 | — | 3.4.33 |
| Ubuntu | 25.04 | 2.41 | — | 3.4.34 |
| Debian | 9 | 2.24 | — | 3.4.22 |
| Debian | 10 | 2.28 | — | 3.4.25 |
| Debian | 11 | 2.31 | — | 3.4.28 |
| Debian | 12 | 2.36 | — | 3.4.30 |
| Debian | 13 | 2.41 | — | 3.4.33 |
| Alpine | 3.16 | — | 1.2.3 | — |
| Alpine | 3.18 | — | 1.2.4 | — |
| Alpine | 3.20 | — | 1.2.5 | — |
| Alpine | 3.22 | — | 1.2.5 | — |
| CentOS | 7 | 2.17 | — | 3.4.19 |
| Rocky Linux | 8 | 2.28 | — | 3.4.25 |
| Rocky Linux | 9 | 2.34 | — | 3.4.29 |
| AlmaLinux | 8 | 2.28 | — | 3.4.25 |
| AlmaLinux | 9 | 2.34 | — | 3.4.29 |
| Fedora | 40 | 2.39 | — | 3.4.33 |
| Fedora | 41 | 2.40 | — | 3.4.33 |
| Fedora | 42 | 2.41 | — | 3.4.34 |
| Amazon Linux | 2 | 2.26 | — | 3.4.24 |
| Amazon Linux | 2023 | 2.34 | — | 3.4.33 |
| openSUSE Leap | 15.6 | 2.38 | — | 3.4.34 |
| Arch Linux | rolling | 2.44 | — | 3.4.36 |

Measured **2026-11-14** on x86-64. Arch and Fedora are rolling, so those rows age;
re-run the script to refresh.

## Reproduce it

```bash
sudo ./harvest-glibc-matrix.sh
# writes /root/glibc-matrix/rows.jsonl — one JSON object per image
```

The script pulls one image at a time, probes it, records a row, then removes the image,
so disk usage stays flat. Pass image names as arguments to probe a subset:

```bash
sudo ./harvest-glibc-matrix.sh ubuntu:24.04 debian:12
```

### How each value is obtained

```sh
ldd --version | head -1                       # glibc
/lib/ld-musl-x86_64.so.1 --version            # musl (version is on line 2)
grep -aoE 'GLIBCXX_3\.[0-9]+(\.[0-9]+)?' \
  /usr/lib/x86_64-linux-gnu/libstdc++.so.6 | sort -V | tail -1   # libstdc++
```

## What does not fix a GLIBCXX error

Copying `libstdc++.so.6` from the newer machine. It gets picked up by the loader and
then fails on glibc, because that newer libstdc++ was built against a newer libc:

```
./app: libstdc++.so.6: version `GLIBCXX_3.4.32' not found
$ LD_LIBRARY_PATH=./lib ldd ./app | grep stdc++
        libstdc++.so.6 => ./lib/libstdc++.so.6      # found, and used
$ LD_LIBRARY_PATH=./lib ./app
./app: libc.so.6: version `GLIBC_2.38' not found
```

Fix it by building against an older image, or with `-static-libstdc++`, or fully
static against musl.

## Related

- Browser ELF inspector (no upload, nothing installed): <https://readelf.com/tools/elf-inspector/>
- Compatibility checker: <https://readelf.com/tools/compatibility-checker/>
- The long-form guide: <https://readelf.com/guides/glibc-version-by-distribution/>

## License

MIT — the data and the script, use either freely.
