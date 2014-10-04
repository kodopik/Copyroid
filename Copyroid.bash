#!/bin/bash
#
# Copyroid
# v.0.2.0
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

set -e

# Help message
function printHelp() {
    echo "Copyroid makes a copy of an Android application."
    echo "Usage: bash ${0} file [ suffix ]"
    echo "e.g. bash ${0} MyApplication.apk COPY"
}

declare -r HELP_LINES="-h|--help"

if [[ ${1} =~ ${HELP_LINES} ]] ;
then
    printHelp
    exit 0
fi

# Original APK file
declare -r ORIG_FILE="$1"; shift

# Suffix (to be added at the end of application and the begin of package names)
if [[ -z ${1} ]]
then
    declare -r SUFFIX="COPY"
else
    declare -r SUFFIX="$1"
fi

declare -r suffix=$(echo ${SUFFIX} | tr [:upper:] [:lower:])

# Files and directories
declare -r ORIG_DIR='./orig'
declare -r TMP_FILE='.tmp.apk'
declare -r MANIFEST="${ORIG_DIR}/AndroidManifest.xml"
declare -r SMALI_DIR="${ORIG_DIR}/smali"
declare -r RES_DIR="${ORIG_DIR}/res"
declare COPY_DIR="${SMALI_DIR}/${suffix}"

if [[ ! -f "$ORIG_FILE" ]]
then
    echo "Wrong input file" >&2
    echo
    printHelp
    exit 1
fi

if [[ ${SUFFIX} =~ [^a-zA-Z0-9] ]]
then
    echo "Suffix must be [a-zA-Z0-9]" >&2
    echo
    printHelp
    exit 2
fi




# We have to add `-o' key while using 2-nd version of `apktool'
declare -r APKTOOL_V=$(apktool --version | awk -F\. '{ print $1 }')

if [[ $APKTOOL_V > 1 ]]
then
    declare -r FOLDER_PARAM='-o'
else
    declare -r FOLDER_PARAM=''
fi



echo '**** DECODING ****'



apktool d -f "$ORIG_FILE" $FOLDER_PARAM "$ORIG_DIR" \
    || exit 3



echo; echo '**** CHANGING ****'



echo -n 'Changing app_name '

declare -r PKG_NAME=$(xmlstarlet sel -t -m "//manifest" -v "@package" ${MANIFEST})
declare -r PKG_VERSION_TMP=$(awk -F\: '/versionName/{ print $2 }' "${ORIG_DIR}/apktool.yml")
declare PKG_VERSION=${PKG_VERSION_TMP//[^0-9a-zA-Z\.\-]/}
declare -r LABEL=$(xmlstarlet sel -t -m "//application" -v "@android:label" ${MANIFEST})
echo $LABEL | grep -q '@string\/' && declare -r -i changeManifest=1 || unset changeManifest

if [[ $changeManifest ]]
then
    # Change strings.xml files
    echo '(strings.xml)...'
    declare -r string=${LABEL/@string\//}
    find "$RES_DIR" -name strings\.xml \
        -exec xmlstarlet ed -L -s "//string[@name='${string}']" -t text -n "string" -v " ${SUFFIX}" {} \;
else
    # Change AndroidManifest.xml file
    echo '(AndroidManifest.xml)...'
    xmlstarlet ed -L -u "//application[@android:label]/@android:label" -v "${LABEL} ${SUFFIX}" ${MANIFEST}
fi



echo 'Changing side authorities...'
xmlstarlet ed -L -u "//provider[@android:authorities]/@android:authorities" -x "concat('${suffix}.',.)" ${MANIFEST}
# can't get why it doesn't run correctly without this rude cheat :(
sed -i 's/="'${suffix}'\.'${suffix}'\./="'${suffix}'./g' ${MANIFEST}



echo 'Changing icon...'

declare -r ICON=$(xmlstarlet sel -t -m "//application" -v "@android:icon" ${MANIFEST})

# Icon file can be in any directory, not only res/drawable
#declare -r string=${ICON/@drawable\//}
declare -r iconstring=${ICON/@*\//}

# TODO: change icon effect from simple negate to something more beautiful
find "$RES_DIR" -name "${iconstring}\.png" \
    -exec convert {} -negate {} \;



echo 'Changing path...'

declare -r RESULT_FILE="${PKG_NAME}_${PKG_VERSION}.apk"
declare -r SCR_DOT_PKG=${PKG_NAME//\./\\\.}
declare -r SCR_SLASH_PKG=${SCR_DOT_PKG//\./\/}
declare -r SLASH_PKG=${PKG_NAME//\./\/}
declare -r DIRS_PATH="${PKG_NAME//\./ }"
declare -r MOVE_DIR="${SMALI_DIR}/${SLASH_PKG}"

if [[ ! -d ${MOVE_DIR} ]]
then
    echo "Klutz developers!
Sorry, you have to make a copy of this application by hand,
'cos clumsy developers have made the path different from the package name.
Maybe, I'll fix it later..." >&2
    exit 4
fi

find "${ORIG_DIR}" -name \*\.smali \
    -exec sed -i 's/\('${SCR_SLASH_PKG}'\)/'${suffix}'\/\1/g' {} \;



echo 'Changing package name in smali...'

find "${ORIG_DIR}" -name \*\.smali \
    -exec sed -i 's/\('${SCR_DOT_PKG}'\)/'${suffix}'\.\1/g' {} \;



echo 'Changing package name in xml...'

find "${ORIG_DIR}" -name \*\.xml \
    -exec sed -i 's/\('${SCR_DOT_PKG}'\)/'${suffix}'\.\1/g' {} \;

sed -i 's/cur_package: .*/cur_package: '${suffix}'\.'${PKG_NAME}'/' "${ORIG_DIR}/apktool.yml"



echo 'Moving directories...'

# Create path recursively...
for dir in $DIRS_PATH
do
    if [[ -d "${COPY_DIR}" ]]
    then
        echo "Directory \"${COPY_DIR}\" already exists. Choose another suffix (which is \"${SUFFIX}\" now)." >&2
        exit 6
    fi
    mkdir "${COPY_DIR}"
    COPY_DIR="${COPY_DIR}/${dir}"
done
# ... and move directory
mv "${MOVE_DIR}" "${COPY_DIR}"



echo; echo '**** BUILDING ****'



apktool b "$ORIG_DIR" $FOLDER_PARAM "$RESULT_FILE" \
    || exit 5



echo 'Zipalign...'

test -f "${TMP_FILE}" && rm "${TMP_FILE}"

if $(zipalign 4 ${RESULT_FILE} "${TMP_FILE}" 2>/dev/null)
then
    mv "${TMP_FILE}" ${RESULT_FILE}
else
    echo; echo "ERROR: Please install \`android-sdk' and add it into \$PATH" >&2
    declare -r -i INSTALL_SDK=1
fi



echo 'Signing...'

if [[ ! -f SIGN.xml ]] 
then
    echo "There is no SIGN.xml file. See SIGN.sample.xml" >&2
else

    declare -r SIGN_PARAMS=$(xmlstarlet sel -t -m "//param[@name]" -o "-" -v "@name" -o " " -v "@value" -o " " SIGN.xml)
    declare -r SIGN_KEY=$(xmlstarlet sel -t -m "//key" -v "//key" SIGN.xml)

    #if $(jarsigner ${SIGN_PARAMS} -signedjar "${TMP_FILE}" ${RESULT_FILE} ${SIGN_KEY})
    jarsigner ${SIGN_PARAMS} -signedjar "${TMP_FILE}" ${RESULT_FILE} ${SIGN_KEY} && declare -r -i JARSIGNER_RES=1 || declare -r -i JARSIGNER_RES=0
    if [[ ${JARSIGNER_RES} ]]
    then
        mv "${TMP_FILE}" "${RESULT_FILE}"
    else
        echo; echo "ERROR: Wrong parameters. Or there is no \`jarsigner' utility. Please install JAVA" >&2
        declare -r -i INSTALL_JAVA=1
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
