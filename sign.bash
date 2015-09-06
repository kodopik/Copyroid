#!/bin/bash

declare -r SIGNFILE='SIGN.xml'
#declare -r SIGNFILE='SIGN.ALTER.xml'

SIGN_PARAMS=`xmlstarlet sel -t -m "//param[@name]" -o "-" -v "@name" -o " " -v "@value" -o " " $SIGNFILE`
SIGN_KEY=`xmlstarlet sel -t -m "//key" -v "//key" $SIGNFILE`
FILE="$1"
TEMP=".tmp.apk"

# ZIPALIGN
zipalign 4 "${FILE}" "${TEMP}" || exit 1

# SIGN
jarsigner ${SIGN_PARAMS} -signedjar "${FILE}" "${TEMP}" ${SIGN_KEY} || exit 2

rm "${TEMP}"

exit 0
