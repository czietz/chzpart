#!/usr/bin/env bash

# Exit on error, unset variables, or failed pipes
set -euo pipefail

# Check argument count
if [[ $# -lt 1 || $# -gt 4 ]]; then
    echo "Usage: $0 [-msdos] <size> [filename] [contentdir]"
    exit 1
fi

if [[ "$1" == "-msdos" ]]; then
    echo "Using MS-DOS-style MBR"
    partstyle="M"
    # shift all following parameters
    shift
else
    echo "Using Atari-style partition table"
    partstyle="A"
fi

size="$1"
filename="${2:-hd.img}"
contentdir="${3:-}"

# Check that size is a non-negative integer
if ! [[ "$size" =~ ^[0-9]+$ ]]; then
    echo "Error: size must be a non-negative integer"
    exit 1
fi

# Check size <= 512
if [[ "$size" -gt 512 ]]; then
    echo "Error: size must be less than or equal to 512 MiB"
    exit 1
fi

# Check size >= 6
if [[ "$size" -lt 6 ]]; then
    echo "Error: size must be greater than or equal to 6 MiB"
    exit 1
fi

# Check that the file does not already exist
if [[ -e "$filename" ]]; then
    echo "Error: file '$filename' already exists"
    exit 1
fi

# Locate chzpart
if command -v chzpart >/dev/null 2>&1; then
    CHZPART="chzpart"
elif [[ -x "./chzpart" ]]; then
    CHZPART="./chzpart"
else
    echo "Error: chzpart not found in PATH or current directory"
    exit 1
fi

# Calculate sizem1 = size - 1
sizem1=$((size - 1))

# Pipe input into chzpart
echo "Creating $size MiB disk image '$filename' ..."
printf "A\n%s\n1\n%s\nY\n" "$partstyle" "$sizem1" | "$CHZPART" "$filename" "$size" > /dev/null

# If contentdir is provided, copy contents using mcopy
if [[ -n "$contentdir" ]]; then
    # Check that contentdir exists and is a directory
    if [[ ! -d "$contentdir" ]]; then
        echo "Error: contentdir '$contentdir' is not a directory"
        exit 1
    fi

    # Check that mcopy is available
    if ! command -v mcopy >/dev/null 2>&1; then
        echo "Error: mcopy not found in PATH"
        exit 1
    fi

    # Copy contents into the image
    echo "Copying directory contents..."
    MTOOLS_NO_VFAT=1 mcopy -i "${filename}@@0x200" -spmv "$contentdir"/* ::
fi

echo "Done!"
