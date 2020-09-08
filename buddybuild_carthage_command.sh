#!/bin/bash
carthage bootstrap $CARTHAGE_VERBOSE --platform ios --color auto --cache-builds

# Workaround to Carthage issue with latest version 0.35.0
# https://github.com/Carthage/Carthage/issues/3003
# Issue still open but error on BB carthage formula file from an arbitrary URL is disabled!
# brew uninstall --force carthage
# brew install https://github.com/Homebrew/homebrew-core/raw/09ceff6c1de7ebbfedb42c0941a48bfdca932c0f/Formula/carthage.rb

carthage version

./carthage_command.sh
