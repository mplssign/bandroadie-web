#!/bin/bash

VERSION_LINE=$(grep "^version:" pubspec.yaml | awk '{print $2}')
VERSION=$(echo $VERSION_LINE | cut -d'+' -f1)
BUILD=$(echo $VERSION_LINE | cut -d'+' -f2)

cat <<EOT > web/version.json
{
  "app_name": "bandroadie",
  "version": "$VERSION",
  "build_number": "$BUILD",
  "package_name": "bandroadie"
}
EOT

echo "Generated version.json → $VERSION+$BUILD"
