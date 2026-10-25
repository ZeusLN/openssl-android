# OpenSSL for Android

OpenSSL built from source as a prefab AAR, for [ZEUS](https://github.com/ZeusLN/zeus). ZEUS's encrypted app database uses op-sqlite's SQLCipher build, which links against this OpenSSL (ZeusLN/zeus#4471). ZEUS downloads the AAR from this repo's releases in `fetch-libraries.sh` and checks it against the sha256 in `fetch-libraries-versions.json`.

## What is built

- OpenSSL `3.6.2`, from the release tarball. Its sha256 is pinned in `build.sh` and was checked against OpenSSL's release signature.
- ABIs `arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`, for API level 28, using NDK `28.0.13004108` in the same digest-pinned builder image as ZEUS's own reproducible build.
- Shared `libcrypto.so` and `libssl.so`, configured with `no-sctp shared`, 16 KB page alignment, `-fstack-protector-strong` and `-D_FORTIFY_SOURCE=2`.
- Headers for each ABI. OpenSSL's generated `configuration.h` differs between 32- and 64-bit targets.

## Reproducing a release

```sh
git checkout v3.6.2-zeus1
./build.sh
cat out/openssl-3.6.2-zeus1.aar.sha256
```

The hash should match the release's `.sha256` file and the value in ZEUS's `fetch-libraries-versions.json`. `build.sh` pins the source hash and the builder image, sets `SOURCE_DATE_EPOCH`, installs to a fixed prefix and writes the AAR as a deterministic zip. Docker is required, and on an arm64 machine the image runs under amd64 emulation.

Every push and pull request builds twice on separate CI runners, and the workflow fails if the two AARs differ. A tag `v<OpenSSL version>-zeus<n>` publishes the AAR and its hash once both builds match.

## Updating

1. Set `OPENSSL_VERSION` and `OPENSSL_SHA256` in `build.sh`, and check the tarball's signature first. Reset the `-zeus<n>` suffix to 1. For a recipe change on the same OpenSSL version, bump the suffix instead.
2. Update `SOURCE_DATE_EPOCH` to the OpenSSL release date.
3. Merge, then tag `v<OPENSSL_VERSION>-zeus<n>`.
4. In ZEUS, update the version and sha256 in `fetch-libraries-versions.json`, and the version in `android/build.gradle` and the POM under `android/openssl`.

## License

The build scripts are Apache-2.0 (`LICENSE`). The OpenSSL license is included in the AAR as `META-INF/LICENSE.txt`.
