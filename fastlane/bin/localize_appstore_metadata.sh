#!/bin/sh

cd "metadata"

find . -name LocalizedStrings.xml | while read fname; do
    LANG=$(dirname $fname)
    echo $LANG

    FIELDS=( "keywords" "description" "name" "subtitle" "release_notes" )
    for FIELD in "${FIELDS[@]}"
    do
        xmlstarlet sel -t -v "/resources/string[@name=\"appstore.$FIELD\"]/text()" "$LANG/LocalizedStrings.xml" | sed -e 's/^"//g' -e 's/"$//g' -e 's/\\"/"/g' | ascii2uni -a Y > "$LANG/$FIELD.txt"
    done 
done