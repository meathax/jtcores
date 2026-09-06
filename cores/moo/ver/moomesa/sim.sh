#!/bin/bash
set -e

OTHER=()
SCENE=
CRC=

while [ $# -gt 0 ]; do
    case $1 in
        -s|--scene)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "Missing scene name" >&2
                exit 1
            fi
            shift
            SCENE=$1
            OTHER+=(-d NOMAIN -d NOSOUND -zoom -video 2 -w)
            if [ ! -d "scenes/$SCENE" ]; then
                echo "Cannot open folder $SCENE"
                exit 1
            fi;;
        --crc)
            CRC=1;;
        --batch) OTHER+=(-batch);;
        *) OTHER+=("$1");;
    esac
    shift
done

if [[ ! -e nvram.bin && -z "$SCENE" ]]; then
    cat <<HELP
This system requires a valid nvram.bin file to boot up properly
Use MAME's moomesa.nv file for the "moomesa" set
HELP
    exit 1
fi

"$BASH" ../game/dump_split.sh --scene "$SCENE" --nvram --fullram

jtsim "${OTHER[@]}"

if [[ -n "$SCENE" ]]; then
    shopt -s nullglob
    frames=(frames/frame_*.jpg frames/frame_*.png)
    if [[ ${#frames[@]} = 0 || ! -s frames/frames.crc ]]; then
        echo "Scene $SCENE did not produce a frame and CRC" >&2
        exit 1
    fi
    # Sort by the zero-padded frame number, including either supported format.
    latest=$(printf '%s\n' "${frames[@]}" | LC_ALL=C sort | tail -n 1)
    extension=${latest##*.}
    cp -- "$latest" "scenes/$SCENE/$SCENE.$extension"
    if [[ ! -e "scenes/$SCENE/$SCENE.crc" || $CRC = 1 ]]; then
        tail -n 1 frames/frames.crc > "scenes/$SCENE/$SCENE.crc"
    else
        if ! diff -q <(tail -n 1 frames/frames.crc) "scenes/$SCENE/$SCENE.crc" > /dev/null; then
            echo "WARNING: the image CRC has changed for scene $SCENE"
            exit 1
        fi
    fi
fi
