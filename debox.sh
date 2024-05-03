#!/usr/bin/env bash

# Date: 2024/05/22
# Author: Aalekh Patel (@aalekhpatel07)
# This script uses Image Magick to remove letterboxing and pillarboxing from images
# by detecting edge-free regions on the image using Canny edge detection.
#
# Usage: $ ./debox.sh foo-with-letterbox.jpg foo-output-letterbox-removed.jpg

set -euxo pipefail

INPUT_IMAGE="$1"
OUTPUT_IMAGE="$2"

echo "Removing letterboxing and pillarboxing from ${INPUT_IMAGE} and writing new image to ${OUTPUT_IMAGE}" >&2

TEMP_IMAGE_TXT="${INPUT_IMAGE%%.*}.tmp.txt"

# Write txt format of canny'd image to a temporary file.
convert ${INPUT_IMAGE} -canny 5x1+10%+20% ${TEMP_IMAGE_TXT}

HEIGHT=$(identify -ping -format "%h" ${INPUT_IMAGE})
WIDTH=$(identify -ping -format "%w" ${INPUT_IMAGE})

# These are populated by find_top_row, find_bottom_row, find_left_col, and find_right_col functions.
ZERO_ROW_FROM_TOP=0
ZERO_ROW_FROM_BOTTOM=$HEIGHT
ZERO_COL_FROM_LEFT=0
ZERO_COL_FROM_RIGHT=$WIDTH

function find_top_row() {
  # Find the largest block of rows from the top edge that is completely free of edges.
  for row in $(seq 0 $HEIGHT);
  do
    local NUM_ZEROS=$(rg "(\d+),${row}: \(0\)  #000000  gray\(0\)" --no-filename -c ${TEMP_IMAGE_TXT})
    # entire row is zeroes (i.e. no pixels are "edge"-y)
    if [[ "${NUM_ZEROS}" -eq ${WIDTH} ]]; then
      # extend the box downwards.
      if [[ "${ZERO_ROW_FROM_TOP}" -lt ${row} ]]; then 
        ZERO_ROW_FROM_TOP=${row}
      fi
    else
      break
    fi
  done
}


function find_bottom_row() {
  # Find the largest block of rows from the bottom edge that is completely free of edges.
  HEIGHT_MINUS_ONE=$(($HEIGHT-1))
  for row in $(seq $HEIGHT_MINUS_ONE -1 1);
  do
    local NUM_ZEROS=$(rg "(\d+),${row}: \(0\)  #000000  gray\(0\)" --no-filename -c ${TEMP_IMAGE_TXT})
    # entire row is zeroes (i.e. no pixels are "edge"-y)
    if [[ "${NUM_ZEROS}" -eq ${WIDTH} ]]; then
      # extend the box upwards.
      if [[ "${ZERO_ROW_FROM_BOTTOM}" -gt ${row} ]]; then 
        ZERO_ROW_FROM_BOTTOM=${row}
      fi
    else
      break
    fi
  done
}


function find_left_col() {
  # Find the largest block of columns from the left edge that is completely free of edges.
  for col in $(seq 0 $WIDTH);
  do
    NUM_ZEROS=$(rg "^${col},(\d+): \(0\)  #000000  gray\(0\)" --no-filename -c ${TEMP_IMAGE_TXT})
    # entire column is zeroes (i.e. no pixels are "edge"-y)
    if [[ "${NUM_ZEROS}" -eq ${HEIGHT} ]]; then
      # extend the box rightwards.
      if [[ "${ZERO_COL_FROM_LEFT}" -lt ${col} ]]; then 
        ZERO_COL_FROM_LEFT=${col}
      fi
    else
      break
    fi
  done
}


function find_right_col() {
  # Find the largest block of columns from the right edge that is completely free of edges.
  WIDTH_MINUS_ONE=$(($WIDTH-1))
  for col in $(seq $WIDTH_MINUS_ONE -1 1);
  do
    NUM_ZEROS=$(rg "^${col},(\d+): \(0\)  #000000  gray\(0\)" --no-filename -c ${TEMP_IMAGE_TXT})
    # entire column is zeroes (i.e. no pixels are "edge"-y)
    if [[ "${NUM_ZEROS}" -eq ${HEIGHT} ]]; then
      if [[ "${ZERO_COL_FROM_RIGHT}" -gt ${col} ]]; then 
      # extend the box leftwards.
        ZERO_COL_FROM_RIGHT=${col}
      fi
    else
      break
    fi
  done
}

CROPPED_WIDTH=
CROPPED_HEIGHT=

function debox() {
  # Determine the region of interest by chopping off the edge-free blocks.
  CROPPED_WIDTH=$(($ZERO_COL_FROM_RIGHT-$ZERO_COL_FROM_LEFT))
  CROPPED_HEIGHT=$(($ZERO_ROW_FROM_BOTTOM-$ZERO_ROW_FROM_TOP))
  CROPPED_ROW_OFFSET=$ZERO_ROW_FROM_TOP
  CROPPED_COL_OFFSET=$ZERO_COL_FROM_LEFT

  # Extract the region of interest.
  convert "${INPUT_IMAGE}"["${CROPPED_WIDTH}x${CROPPED_HEIGHT}+${CROPPED_COL_OFFSET}+${CROPPED_ROW_OFFSET}"] "${OUTPUT_IMAGE}"
}

find_top_row
find_bottom_row
find_left_col
find_right_col

# If the entire image is edge-free, then swap the left/right and top/bottom back
# since they would've effectively swapped places during the linear scan.
if [[ ${ZERO_ROW_FROM_TOP} -gt ${ZERO_ROW_FROM_BOTTOM} ]]; then
  ZERO_ROW_FROM_TOP_TMP=${ZERO_ROW_FROM_TOP}
  ZERO_ROW_FROM_TOP=${ZERO_ROW_FROM_BOTTOM}
  ZERO_ROW_FROM_BOTTOM=${ZERO_ROW_FROM_TOP_TMP}
fi
if [[ ${ZERO_COL_FROM_LEFT} -gt ${ZERO_COL_FROM_RIGHT} ]]; then
  ZERO_COL_FROM_LEFT_TMP=${ZERO_COL_FROM_LEFT}
  ZERO_COL_FROM_LEFT=${ZERO_COL_FROM_RIGHT}
  ZERO_COL_FROM_RIGHT=${ZERO_COL_FROM_LEFT_TMP}
fi

echo "top: ${ZERO_ROW_FROM_TOP} bottom: ${ZERO_ROW_FROM_BOTTOM} left: ${ZERO_COL_FROM_LEFT} right: ${ZERO_COL_FROM_RIGHT}" >&2

debox

echo "original: [${HEIGHT}x${WIDTH}] ${INPUT_IMAGE} -> de-letterboxed/pillarboxed: [${CROPPED_HEIGHT}x${CROPPED_WIDTH}] ${OUTPUT_IMAGE}" >&2

# Clean up the temporary txt representation
rm ${TEMP_IMAGE_TXT}
