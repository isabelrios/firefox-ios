#!/usr/bin/env python

from lxml import html
from lxml import etree
import copy
import json
import os
import requests
import shutil
import subprocess
import urllib

header = """\
<!-- This Source Code Form is subject to the terms of the Mozilla Public
   - License, v. 2.0. If a copy of the MPL was not distributed with this
   - file, You can obtain one at http://mozilla.org/MPL/2.0/. -->

"""

ns = { "search": "http://www.mozilla.org/2006/browser/search/" }

def main():
    if os.path.exists("SearchPlugins"):
        shutil.rmtree("SearchPlugins")
    os.makedirs("SearchPlugins")

    # Copy the default en search engines since they aren't in an l10n repo.
    enPluginsSrc = os.path.join("SearchOverlays", "en")
    enPluginsDst = os.path.join("SearchPlugins", "en")
    shutil.copytree(enPluginsSrc, enPluginsDst)

    locales = getLocaleList()
    supportedLocales = getSupportedLocales()
    for locale in locales:
        if (locale not in supportedLocales):
            print("skipping unsupported locale: %s" % locale)
            continue

        files = getFileList(locale)
        if files == None:
            print("no files for locale: %s" % locale)
            continue

        print("  found search plugins")

        directory = os.path.join("SearchPlugins", locale)
        if not os.path.exists(directory):
            os.makedirs(directory)

        # Get the default search engine for this locale.
        default = getDefault(locale)
        if default == None:
            continue
        saveDefault(locale, default)

        for file in files:
            path = os.path.join(directory, file)

            # If there are any locale-specific overrides, use them instead of the downloaded file.
            overlayPath = os.path.join("SearchOverlays", locale, file)
            if os.path.exists(overlayPath):
                print("  copying override: %s..." % file)
                shutil.copy(overlayPath, path)
                continue

            downloadedFile = getFile(locale, file)
            name, extension = os.path.splitext(file)

            # Apply iOS-specific overlays for this engine if they are defined.
            if extension == ".xml":
                engine = name.split("-")[0]
                overlay = overlayForEngine(engine)
                if overlay:
                    plugin = etree.parse(downloadedFile)
                    for action in overlay:
                        if action.tag == "replace":
                            overlayReplace(target=action.get("target"), replacement=action[0], plugin=plugin)
                        elif action.tag == "append":
                            overlayAppend(parent=action.get("parent"), child=action[0], plugin=plugin)
                    contents = header + etree.tostring(plugin.getroot(), encoding="utf-8", pretty_print=True)
                    with open(path, "w") as outfile:
                        outfile.write(contents)
                    continue

            # Otherwise, just use the downloaded file as is.
            shutil.move(downloadedFile, path)

def getSupportedLocales():
    supportedLocales = subprocess.Popen("./get_supported_locales.swift", stdout=subprocess.PIPE).communicate()[0]
    return json.loads(supportedLocales.replace("_", "-"))

def overlayForEngine(engine):
    path = os.path.join("SearchOverlays", "%s.xml" % engine)
    if not os.path.exists(path):
        return None
    overlay = etree.parse(path)
    return overlay.getroot().getchildren()

def overlayReplace(target, replacement, plugin):
    for element in plugin.xpath(target, namespaces=ns):
        replacementCopy = copy.deepcopy(replacement)
        element.getparent().replace(element, replacementCopy)

        # Try to preserve indentation.
        replacementCopy.tail = element.tail

def overlayAppend(parent, child, plugin):
    for element in plugin.xpath(parent, namespaces=ns):
        childCopy = copy.deepcopy(child)
        element.append(childCopy)

        # Try to preserve indentation.
        childCopy.tail = "\n"
        previous = childCopy.getprevious()
        if previous is not None:
            prevPrevious = previous.getprevious()
            if prevPrevious is not None:
                previous.tail = prevPrevious.tail

def getLocaleList():
    response = requests.get('https://hg.mozilla.org/releases/mozilla-aurora/raw-file/default/mobile/android/locales/all-locales')
    return response.text.strip().split("\n")

def getFileList(locale):
    print("scraping: %s..." % locale)
    url = "https://hg.mozilla.org/releases/l10n/mozilla-aurora/%s/file/default/mobile/searchplugins" % locale
    response = requests.get(url)
    if not response.ok:
        return

    tree = html.fromstring(response.content)
    return tree.xpath('//a[@class="list"]/text()')

def getFile(locale, file):
    print("  downloading: %s..." % file)
    url = "https://hg.mozilla.org/releases/l10n/mozilla-aurora/%s/raw-file/default/mobile/searchplugins/%s" % (locale, file)
    result = urllib.urlretrieve(url)
    return result[0]

def getDefault(locale):
    url = "https://hg.mozilla.org/releases/l10n/mozilla-aurora/%s/raw-file/default/mobile/chrome/region.properties" % locale
    response = requests.get(url)
    if not response.ok:
        return

    lines = response.text.strip().split("\n")
    for line in lines:
        values = line.strip().split("=")
        if len(values) == 2 and values[0].strip() == "browser.search.defaultenginename":
            default = values[1].strip()
            print("  default: %s" % default)
            return default

def saveDefault(locale, default):
    directory = os.path.join("SearchPlugins", locale, "default.txt")
    file = open(directory, "w")
    file.write(default.encode("UTF-8"))

if __name__ == "__main__":
        main()
