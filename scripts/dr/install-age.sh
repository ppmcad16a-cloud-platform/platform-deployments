#!/bin/sh
# Downloads the age encryption tool into ./tools and refuses to continue
# if the file does not match the fingerprint GitHub publishes for it.
set -eu
AGE_VERSION=1.3.2
AGE_SHA256=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10
mkdir -p tools
cd tools
curl -fsSL -o age.tar.gz "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"
echo "${AGE_SHA256}  age.tar.gz" | sha256sum -c -
tar -xzf age.tar.gz --strip-components=1 age/age
rm age.tar.gz
./age --version
