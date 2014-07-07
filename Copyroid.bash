#!/bin/bash
#
# Copyroid
# v.0.1.3
#
# Makes a copy of an Android application:
#   you will be able to install both .apk files
#   and use two same applications simultaneously.
# (c) Anton 'KodopiK' Konoplev, 2013-2014
# 
# Dependencies:
# `apktool'
# `xmlstarlet'
# `sed' (GNU sed with `--in-place' key)
# `awk'
# `convert' (from ImageMagick)
# `zipalign' (from Android SDK)
# `jarsigner' (fom JAVA)



function printHelp() {
    echo "Copyroid makes a copy of an Android application."
    echo "Usage: bash ${0} file [ suffix ]"
    echo "e.g. bash ${0} MyApplication.apk COPY"
}



HELP_LINES="-h|--help"
if [[ ${1} =~ ${HELP_LINES} ]] ;
then
    printHelp
    exit 0
fi



ORIG_FILE="$1"
SUFFIX="$2"
ORIG_DIR='./orig'
MANIFEST="${ORIG_DIR}/AndroidManifest.xml"
SMALI_DIR="${ORIG_DIR}/smali"
RES_DIR="${ORIG_DIR}/res"
COPY_DIR="${SMALI_DIR}/copy"

if [[ ! -f "$ORIG_FILE" ]]
then
    echo "Wrong input file"
    printHelp
    exit 1
fi

if [[ ${SUFFIX} =~ [^a-zA-Z0-9] ]]
then
    echo "Suffix must be [a-zA-Z0-9]"
    printHelp
    exit 2
fi

if [[ -z ${SUFFIX} ]]
then
    SUFFIX="COPY"
fi



# We have to add `-o' key while using 2-nd version of `apktool'
APKTOOL_V=`apktool --version | awk -F\. '{ print $1 }'`

if [[ $APKTOOL_V -gt 1 ]]
then
    FOLDER_PARAM='-o'
else
    FOLDER_PARAM=''
fi



echo '**** DECODING ****'



apktool d -f "$ORIG_FILE" $FOLDER_PARAM "$ORIG_DIR" \
    || exit 3



echo; echo '**** CHANGING ****'



echo -n 'Changing app_name '

PKG_NAME=`xmlstarlet sel -t -m "//manifest" -v "@package" ${MANIFEST}`
PKG_VERSION=`grep versionName "${ORIG_DIR}/apktool.yml" | awk -F\: '{ print $2 }'`
PKG_VERSION=${PKG_VERSION//[^0-9a-zA-Z\.\-]/}
LABEL=`xmlstarlet sel -t -m "//application" -v "@android:label" ${MANIFEST}`
echo $LABEL | grep -q '@string\/' && changeManifest=1 || unset changeManifest

if [[ $changeManifest ]]
then
    # Change strings.xml files
    echo '(strings.xml)...'
    string=${LABEL/@string\//}
    find "$RES_DIR" -name strings\.xml \
        -exec xmlstarlet ed -L -s "//string[@name='${string}']" -t text -n "string" -v " ${SUFFIX}" {} \;
else
    # Change AndroidManifest.xml file
    echo '(AndroidManifest.xml)...'
    xmlstarlet ed -L -u "//application[@android:label]/@android:label" -v "${LABEL} ${SUFFIX}" ${MANIFEST}
fi



echo 'Changing side authorities...'
xmlstarlet ed -L -u "//provider[@android:authorities]/@android:authorities" -x "concat('copy.',.)" ${MANIFEST}
# rude hack :(
sed -i 's/="copy\.copy\./="copy./g' ${MANIFEST}



echo 'Changing icon...'

ICON=`xmlstarlet sel -t -m "//application" -v "@android:icon" ${MANIFEST}`

# Icon file can be in any directory, not only res/drawable
#string=${ICON/@drawable\//}
string=${ICON/@*\//}

# TODO: change icon effect from simple negate to something more beautiful
find "$RES_DIR" -name "${string}\.png" \
    -exec convert {} -negate {} \;



echo 'Changing path...'

RESULT_FILE="${PKG_NAME}_${PKG_VERSION}.apk"
SCR_DOT_PKG=${PKG_NAME//\./\\\.}
SCR_SLASH_PKG=${SCR_DOT_PKG//\./\/}
SLASH_PKG=${PKG_NAME//\./\/}
DIRS_PATH="${PKG_NAME//\./ }"
MOVE_DIR="${SMALI_DIR}/${SLASH_PKG}"

if [[ ! -d ${MOVE_DIR} ]]
then
    echo "Klutz developers!"
    echo "Sorry, you have to make a copy of this application by hand,"
    echo "'cos clumsy developers have made the path different from the package name."
    echo "Maybe, I'll fix it later..."
    exit 4
fi

find ./orig -name \*\.smali \
    -exec sed -i 's/\('${SCR_SLASH_PKG}'\)/copy\/\1/g' {} \;



echo 'Changing package name in smali...'

find ./orig -name \*\.smali \
    -exec sed -i 's/\('${SCR_DOT_PKG}'\)/copy\.\1/g' {} \;



echo 'Changing package name in xml...'

find ./orig -name \*\.xml \
    -exec sed -i 's/\('${SCR_DOT_PKG}'\)/copy\.\1/g' {} \;

sed -i 's/cur_package: .*/cur_package: copy\.'${PKG_NAME}'/' "${ORIG_DIR}/apktool.yml"



echo 'Moving directories...'

for dir in $DIRS_PATH
do
    mkdir "${COPY_DIR}"
    COPY_DIR="${COPY_DIR}/${dir}"
done

mv "${MOVE_DIR}" "${COPY_DIR}"



echo; echo '**** BUILDING ****'



apktool b "$ORIG_DIR" $FOLDER_PARAM "$RESULT_FILE" \
    || exit 5



echo 'Zipalign...'

test -f .tmp.apk && rm .tmp.apk

if `zipalign 4 ${RESULT_FILE} .tmp.apk 2>/dev/null`
then
    mv .tmp.apk ${RESULT_FILE}
else
    echo; echo "ERROR: Please install \`android-sdk' and add it into \$PATH"
    INSTALL_SDK=1
fi



echo 'Signing...'

if [[ ! -f SIGN.xml ]] 
then
    echo "There is no SIGN.xml file. See SIGN.sample.xml"
else

    SIGN_PARAMS=`xmlstarlet sel -t -m "//param[@name]" -o "-" -v "@name" -o " " -v "@value" -o " " SIGN.xml`
    SIGN_KEY=`xmlstarlet sel -t -m "//key" -v "//key" SIGN.xml`

    #if `jarsigner ${SIGN_PARAMS} -signedjar .tmp.apk ${RESULT_FILE} ${SIGN_KEY}`
    jarsigner ${SIGN_PARAMS} -signedjar .tmp.apk ${RESULT_FILE} ${SIGN_KEY} && JARSIGNER_RES=1 || JARSIGNER_RES=0
    if [[ ${JARSIGNER_RES} ]]
    then
        mv .tmp.apk ${RESULT_FILE}
    else
        echo; echo "ERROR: Wrong parameters. Or there is no \`jarsigner' utility. Please install JAVA"
        INSTALL_JAVA=1
    fi
fi



echo; echo; echo "Your ${SUFFIX} file is \`${RESULT_FILE}'"

if [[ ${INSTALL_JAVA} ]]
then
    echo "Don't forget to sign it manually."
fi

if [[ ${INSTALL_SDK} ]]
then
    echo "And you'd better zipalign it..."
fi

echo



exit 0
