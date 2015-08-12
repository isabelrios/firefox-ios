#!/bin/sh

if [ ! -d Client.xcodeproj ]; then
  echo "Please run this from the project root that contains Client.xcodeproj"
  exit 1
fi

if [ -d firefox-ios-l10n ]; then
  echo "There already is a firefox-ios-l10n checkout. Aborting to let you decide what to do."
  exit 1
fi

svn co --non-interactive --trust-server-cert https://svn.mozilla.org/projects/l10n-misc/trunk/firefox-ios firefox-ios-l10n

#
# TODO Add incomplete locales here that are NOT to be included.
# TODO Look at https://l10n.mozilla-community.org/~flod/webstatus/?product=firefox-ios to find out which locales are not at 100%
#

INCOMPLETE_LOCALES=(
    "da"
    "eo"
    "es"
    "gl"
    "is"
    "ko"
    "lt"
    "ru"
    "sk"
    "son"
    "tl"
    "uz"
    "zh-CN"
    "zh-TW"
)

if [ $1 == "--only-complete" ]; then
  for i in "${!INCOMPLETE_LOCALES[@]}"; do
    echo "Removing incomplete locale ${INCOMPLETE_LOCALES[$i]}"
    rm -rf "firefox-ios-l10n/${INCOMPLETE_LOCALES[$i]}"
  done
fi

# Cleanup files (remove unwanted sections, map sv-SE to sv)
scripts/update-xliff.py firefox-ios-l10n

# Remove unwanted sections like Info.plist files and $(VARIABLES)
scripts/xliff-cleanup.py firefox-ios-l10n/*/*.xliff

# Export xliff files to individual .strings files
rm -rf localized-strings && mkdir localized-strings
scripts/xliff-to-strings.py firefox-ios-l10n localized-strings

# Modify the Xcode project to reference the strings files we just created
scripts/strings-import.py Client.xcodeproj localized-strings

