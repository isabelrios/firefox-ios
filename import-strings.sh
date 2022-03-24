'''
#rm -rf firefoxios-l10n
#git clone --depth 1 https://github.com/mozilla-l10n/firefoxios-l10n firefoxios-l10n || exit 1

echo "Creating LocalizationTools repo"
rm -rf LocalizationTools
git clone --depth 1 git@github.com:mozilla-mobile/LocalizationTools.git LocalizationTools || exit 1
'''
echo "\n\n[*] Building tools/Localizations"
(cd LocalizationTools && swift build)

echo "\n\n[*] Importing Strings - takes a minute. (output in import-strings.log)"
(cd LocalizationTools && swift run LocalizationTools \
  --import \
  --project-path "$PWD/../Client.xcodeproj" \
  --l10n-project-path "$PWD/../firefoxios-l10n") > import-strings.log 2>&1

echo "\n\n[!] Strings have been imported. You can now create a PR."
