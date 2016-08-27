#!/bin/sh

# Converts a file into a fixed-size disk image, for use by the DCPU.
# Usage: ./mkdisk.sh <input file> <output file>

INFILE=$1
OUTFILE=$2

function usage {
  echo "Usage: $0 input output"
}

if [ "$INFILE" = "" ]; then
  usage
  exit 1
fi

if [ "$OUTFILE" = "" ]; then
  usage
  exit 1
fi

# Create the blank file, big enough to be a disk.
dd if=/dev/zero of=$OUTFILE bs=1474560 count=1

# Determine the size of the input file.
SIZESTR=`du -b $INFILE`
set -- $SIZESTR
SIZE=$1

echo Copying $SIZE bytes to disk image...

# Copy over exactly that amount into our new file.
dd if=$INFILE of=$OUTFILE bs=$SIZE count=1 conv=notrunc

