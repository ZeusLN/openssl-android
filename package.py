"""Packages the OpenSSL builds in build.sh's work directory as a prefab AAR.

The zip is deterministic: sorted entries, fixed timestamps (SOURCE_DATE_EPOCH)
and fixed file modes, so two builds of the same inputs are byte-identical.

Each ABI gets its own include directory under
prefab/modules/<module>/libs/android.<abi>/include, which prefab uses in place
of the module's include directory. OpenSSL's generated headers differ between
32- and 64-bit targets (configuration.h sets THIRTY_TWO_BIT or
SIXTY_FOUR_BIT_LONG), so one shared copy would be wrong for some ABIs. The
module-level include directory holds the arm64-v8a copy for tools that do not
read per-ABI headers.
"""

import argparse
import json
import os
import time
import zipfile

MODULES = {"crypto": "libcrypto.so", "ssl": "libssl.so"}

parser = argparse.ArgumentParser()
parser.add_argument("--work", required=True)
parser.add_argument("--abis", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--api", required=True, type=int)
parser.add_argument("--ndk", required=True, type=int)
parser.add_argument("--license", required=True)
parser.add_argument("--out", required=True)
args = parser.parse_args()

abis = args.abis.split()
date = time.gmtime(int(os.environ["SOURCE_DATE_EPOCH"]))[:6]
entries = {}


def add(name, data):
    entries[name] = data if isinstance(data, bytes) else data.encode()


def add_json(name, value):
    add(name, json.dumps(value, separators=(",", ":"), sort_keys=True))


def lib_dir(abi):
    for name in ("lib", "lib64"):
        path = os.path.join(args.work, "install", abi, name)
        if os.path.exists(os.path.join(path, "libcrypto.so")):
            return path
    raise SystemExit(f"no libcrypto.so installed for {abi}")


def add_headers(prefix, abi):
    root = os.path.join(args.work, "install", abi, "include")
    for dirpath, _, files in os.walk(root):
        for f in files:
            path = os.path.join(dirpath, f)
            rel = os.path.relpath(path, root)
            with open(path, "rb") as fh:
                add(f"{prefix}/include/{rel}", fh.read())


add(
    "AndroidManifest.xml",
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
    'package="app.zeusln.thirdparty.openssl">\n'
    f'    <uses-sdk android:minSdkVersion="{args.api}" />\n'
    "</manifest>\n",
)
with open(args.license, "rb") as fh:
    add("META-INF/LICENSE.txt", fh.read())
add_json(
    "prefab/prefab.json",
    {"name": "openssl", "schema_version": 1, "dependencies": [], "version": args.version},
)

for module, library in MODULES.items():
    base = f"prefab/modules/{module}"
    add_json(f"{base}/module.json", {})
    add_headers(base, "arm64-v8a" if "arm64-v8a" in abis else abis[0])
    for abi in abis:
        libs = f"{base}/libs/android.{abi}"
        add_json(f"{libs}/abi.json", {"abi": abi, "api": args.api, "ndk": args.ndk, "stl": "none"})
        with open(os.path.join(lib_dir(abi), library), "rb") as fh:
            add(f"{libs}/{library}", fh.read())
        add_headers(libs, abi)

with zipfile.ZipFile(args.out, "w") as zf:
    for name in sorted(entries):
        info = zipfile.ZipInfo(name, date_time=date)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o644 << 16
        zf.writestr(info, entries[name], compresslevel=9)
