#!/bin/bash
#
# Copyroid
# v.0.1
#
# Makes a copy of an Android application:
#   you will be able to install both .apk files
#   and use two same applications simultaneously.
# (c) Anton 'KodopiK' Konoplev, 2013-2014
# 
# Dependencies:
# - apktool
# - xmlstarlet
# - sed (GNU sed with '--in-place' key)
# - awk
# - convert (from ImageMagick)

ORIG_FILE=$1
test -f "$ORIG_FILE" \
    || exit 1
ORIG_DIR='./orig'
MANIFEST="${ORIG_DIR}/AndroidManifest.xml"
SMALI_DIR="${ORIG_DIR}/smali"
RES_DIR="${ORIG_DIR}/res"
COPY_DIR="${SMALI_DIR}/copy"

## Changed to `apktool -f'
#test -d "$ORIG_DIR" && rm -r "$ORIG_DIR"

APKTOOL_V=`apktool --version | awk -F\. '{ print $1 }'`
if [[ $APKTOOL_V -gt 1 ]]
then
    FOLDER_PARAM='-o'
else
    FOLDER_PARAM=''
fi

echo '**** DECODING ****'

apktool d -f "$ORIG_FILE" $FOLDER_PARAM "$ORIG_DIR" \
    || exit 2

echo
echo '**** CHANGING ****'

PKG_NAME=`xmlstarlet sel -t -m "//manifest" -v "@package" ${MANIFEST}`

## apktool v.2.x deletes versionName from manifest
#if [[ $APKTOOL_V -gt 1 ]]
#then
    PKG_VERSION=`grep versionName "${ORIG_DIR}/apktool.yml" | awk -F\: '{ print $2 }'`
    PKG_VERSION=${PKG_VERSION//[^0-9a-zA-Z\.\-]/}
#else
#    PKG_VERSION=`xmlstarlet sel -t -m "//manifest" -v "@android:versionName" ${MANIFEST}`
#fi

LABEL=`xmlstarlet sel -t -m "//application" -v "@android:label" ${MANIFEST}`
echo $LABEL | grep -q '@string\/' && changeManifest=1 || unset changeManifest

echo -n 'Changing app_name '

if [[ $changeManifest ]]
then
    # Change strings.xml files
    echo '(strings.xml)...'
    string=${LABEL/@string\//}
    find "$RES_DIR" -name strings\.xml -exec xmlstarlet ed -L -s "//string[@name='${string}']" -t text -n "string" -v " COPY" -n {} \;
else
    # Change AndroidManifest.xml file
    echo '(AndroidManifest.xml)...'
    xmlstarlet ed -L -u "//application[@android:label]/@android:label" -v "${LABEL} COPY" ${MANIFEST}
fi

ICON=`xmlstarlet sel -t -m "//application" -v "@android:icon" ${MANIFEST}`

echo 'Changing icon...'
string=${ICON/@drawable\//}
find "$RES_DIR" -name "${string}\.png" -exec convert {} -negate {} \;

RESULT_FILE="${PKG_NAME}_${PKG_VERSION}.apk"

SCR_DOT_PKG=${PKG_NAME//\./\\\.}
SCR_SLASH_PKG=${SCR_DOT_PKG//\./\/}
SLASH_PKG=${PKG_NAME//\./\/}

DIRS_PATH="${PKG_NAME//\./ }"
MOVE_DIR="${SMALI_DIR}/${SLASH_PKG}"

echo 'Changing path...'
find ./orig -name \*\.smali -exec sed -i 's/\('${SCR_SLASH_PKG}'\)/copy\/\1/g' {} \;

echo 'Changing package name in smali...'
find ./orig -name \*\.smali -exec sed -i 's/\('${SCR_DOT_PKG}'\)/copy\.\1/g' {} \;

echo 'Changing package name in xml...'
find ./orig -name \*\.xml -exec sed -i 's/\('${SCR_DOT_PKG}'\)/copy\.\1/g' {} \;

sed -i 's/cur_package: .*/cur_package: copy\.'${PKG_NAME}'/' "${ORIG_DIR}/apktool.yml"

echo 'Moving directories...'
for dir in $DIRS_PATH
do
    mkdir "${COPY_DIR}"
    COPY_DIR="${COPY_DIR}/${dir}"
done

mv "${MOVE_DIR}" "${COPY_DIR}"

echo
echo '**** BUILDING ****'

apktool b "$ORIG_DIR" $FOLDER_PARAM "$RESULT_FILE" \
    || exit 3

exit 0
