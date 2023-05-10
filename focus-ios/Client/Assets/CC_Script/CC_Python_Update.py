import requests
import filecmp
import shutil
import os

MOZILLA_CENTRAL_URL = "https://hg.mozilla.org/mozilla-central/raw-file/tip/"
GITHUB_ACTIONS_PATH = "./Client/Assets/CC_Script/"
GITHUB_ACTIONS_TMP_PATH = f"{GITHUB_ACTIONS_PATH}tmp/"


FILES_TO_DOWNLOAD = [
    "toolkit/components/formautofill/Constants.ios.mjs",
    "toolkit/modules/CreditCard.sys.mjs",
    "toolkit/components/formautofill/shared/CreditCardRuleset.sys.mjs",
    "toolkit/components/formautofill/shared/FieldScanner.sys.mjs",
    "toolkit/components/formautofill/FormAutofill.ios.sys.mjs",
    "toolkit/components/formautofill/FormAutofill.sys.mjs",
    "toolkit/components/formautofill/FormAutofillChild.ios.sys.mjs",
    "toolkit/components/formautofill/shared/FormAutofillHandler.sys.mjs",
    "toolkit/components/formautofill/shared/FormAutofillHeuristics.sys.mjs",
    "toolkit/components/formautofill/shared/FormAutofillNameUtils.sys.mjs",
    "toolkit/components/formautofill/FormAutofillSection.ios.sys.mjs",
    "toolkit/components/formautofill/FormAutofillSection.sys.mjs",
    "toolkit/components/formautofill/shared/FormAutofillUtils.sys.mjs",
    "toolkit/modules/FormLikeFactory.sys.mjs",
    "toolkit/components/formautofill/shared/FormStateManager.sys.mjs",
    "toolkit/components/formautofill/Helpers.ios.mjs",
    "toolkit/components/formautofill/shared/HeuristicsRegExp.sys.mjs",
    "toolkit/components/formautofill/shared/LabelUtils.sys.mjs",
    "toolkit/components/passwordmgr/LoginManager.shared.mjs",
    "toolkit/components/formautofill/Overrides.ios.js",
    "toolkit/modules/third_party/fathom/fathom.mjs",
]


# Methods related to file download, compare, copy contents and removal

def downloadTemporaryFileToCompare(file_info):
    reqHeader = {"Cache-Control": "no-cache", "Pragma": "no-cache"}
    try:
        response = requests.get(file_info["url"], stream=True, headers=reqHeader)
        try:
            file = open(file_info["tmp_path"], "w")
            file.close()
        except:
            print("Could not write to the file")
        with open(file_info["tmp_path"], "wb") as f:
            for chunk in response.iter_content():
                f.write(chunk)
    except requests.exceptions.HTTPError as err:
        raise SystemExit(err)

def compare_file(file1, file2):
    result = filecmp.cmp(file1, file2)
    print("comparing two files -> ?", result)
    return result

def copyContents(fromFile, toFile):
    print("copying contents")
    with open(fromFile, "rb") as f2, open(toFile, "wb") as f1:
        shutil.copyfileobj(f2, f1)

def removeFile(fileToRemove):
    if os.path.exists(fileToRemove):
        os.remove(fileToRemove)
        return True
    else:
        print("Nothing to remove, all clear")
        return False

def getFileInfo(path):
    filename = os.path.basename(path)
    return {
        "filename": filename,
        "url": MOZILLA_CENTRAL_URL + path,
        "path": GITHUB_ACTIONS_PATH + filename,
        "tmp_path": GITHUB_ACTIONS_TMP_PATH + filename,
    }

def removeTmpFiles():
    for file in FILES_TO_DOWNLOAD:
        removeFile(GITHUB_ACTIONS_TMP_PATH + file)

def createTmpDirectory():
    if os.path.exists(GITHUB_ACTIONS_TMP_PATH) == False:
        os.mkdir(GITHUB_ACTIONS_TMP_PATH)

def removeTmpDirectory():
    if os.path.exists(GITHUB_ACTIONS_TMP_PATH):
        os.rmdir(GITHUB_ACTIONS_TMP_PATH)

# main
def main():
    # create tmp directory
    createTmpDirectory()

    for file in FILES_TO_DOWNLOAD:
        file_info = getFileInfo(file)
        # download file to compare changes
        downloadTemporaryFileToCompare(file_info)

        # move file if it does not exist
        if os.path.exists(file_info["path"]) == False:
            shutil.move(file_info["tmp_path"], file_info["path"])
        else:
            # compare if there are any changes with the file
            # downloaded vs what we currently have on disk
            compare_file_result = compare_file(file_info["tmp_path"], file_info["path"])
            if compare_file_result == False:
                copyContents(file_info["tmp_path"], file_info["path"])
            else:
                print("No change, do nothing")

        # remove temp downloaded file for cleanup
        removeFile(file_info["tmp_path"])

    # cleanup tmp directory
    removeTmpDirectory()

if __name__ == "__main__":
    main()