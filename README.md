# CHZ Atari Disk Partitioning Tool

**Version 0.3**

## Overview

The **CHZ Atari Disk Partitioning Tool** is an interactive utility for partitioning Atari-compatible hard disks and disk images. It can be used:

* **Directly on Atari systems** (real hardware or emulators) that provide XHDI support
* **On non-Atari systems** (such as modern PCs) using disk image files

The tool allows you to create a new partition layout and initialize partitions with a FAT16 file system suitable for Atari systems.

⚠️ **Warning:** Partitioning a disk or disk image will **irreversibly erase all existing data** on it.

---

## Supported Systems and Requirements

### On Atari Systems

* Atari ST/STE/TT/Falcon or compatible or Firebee
* **XHDI support is required**
  * Available in EmuTOS (PRG version and ROM versions sized **256 KiB and above**)

* Compatible storage (ACSI, IDE, SCSI, etc., depending on your setup)

### On Non-Atari Systems

* The tool operates on **disk image files** instead of real hard disks
* Useful for preparing images for emulators such as Hatari

---

## Starting the Program

### On Atari Systems

* Run `68000/CHZPART.TOS`  on Atari ST/STE/TT/Falcon or compatible systems
* Run `FIREBEE/CHZPART.TOS` on the Firebee

### On Non-Atari Systems

#### Using an Existing Disk Image

```text
chzpart disk_image.img
```

#### Creating a New Disk Image

```text
chzpart disk_image.img size_in_MiB
```

Example:

```text
chzpart mydisk.img 512
```

Creates a new 512 MiB disk image and starts the partitioning process.

If the image file already exists when creating a new one, the program will abort to prevent accidental data loss.

---

## Interactive Operation

Once started, the program is **menu-driven** and guides you through the partitioning process step by step. You can always quit the program without making changes to the disk by pressing `Q` + `[Enter]` at the respective prompts.

### 1. Select Hard Disk

* On Atari systems: choose from detected physical hard disks
* On non-Atari systems: confirm the selected disk image

If no disks are found, the program exits.

---

### 2. Select Partition Type

You can choose between:

* **MS-DOS**

  * Compatible with:

    * EmuTOS
    * Windows
    * Linux
    * macOS
  * Maximum partition size **2047 MiB**
* **Atari  TOS 1.04 and above**
  * Compatible with:

    * EmuTOS
    * Atari TOS 1.04 and above
  * Maximum partition size **512 MiB**
* **Atari  TOS 1.00 and above**
  * Compatible with:

    * EmuTOS
    * All versions of Atari TOS
  * Maximum partition size **256 MiB**
* **Atari  TOS 4.04 and above**
  * Compatible with:

    * EmuTOS
    * Atari TOS 4.04 (for the Atari Falcon)
  * Maximum partition size **1024 MiB**

Choose the type that best matches how the disk will be used.

---

### 3. IDE byte Swapping (Atari Systems)

You may be asked whether to enable **byte swapping** for IDE hard disks:

* **Yes** – Enable byte swapping

  * Recommended for “dumb” IDE interfaces, where it improves data exchange compatibility with other systems (PC, Mac)
* **No** – Disable byte swapping

  * Recommended for best performance

⚠️ Always choose **no** for “smart” IDE interfaces that have hardware byte swapping.

Note: This option is only available when partitioning an IDE hard disk with MS-DOS partitions, and only when running under EmuTOS.

---

### 4. Number of Partitions

* You can create **1 to 14 partitions**
* The program ensures that partition sizes remain valid and within disk limits

---

### 5. Partition Sizes

For each partition, enter its size in **MiB** (1024 × 1024 bytes)

The tool:

* Automatically calculates valid minimum and maximum sizes
* Prevents overlapping or oversized partitions

---

### 6. Confirmation

Before any changes are written, you must confirm:

* **Partition disk** – Proceed and erase all existing data
* **Discard changes and exit** – Abort without modifying the disk

Nothing is written until you explicitly confirm.

---

## What the Tool Does

When confirmed, the program will:

1. Create a new partition table
2. Initialize each partition
3. Create a **FAT16 file system** on each partition

A progress message is shown while the disk is being partitioned.

---

## Limits and Notes

* Atari partitions (supported by EmuTOS and Atari TOS) are limited to **256, 512 or 1024 MiB** depending on the version of Atari TOS.
* MS-DOS partitions (supported by EmuTOS, too) are limited to **2047 MiB**
* Hybrid “TOS & Windows” partitioning schemes are deliberately not supported as they tend to cause subtle incompatibilities, e.g., on Linux
* **FAT16** is used for maximum compatibility
* Other file systems (ext2, FAT32, …) are deliberately not supported to keep the tool simple to use
* The tool is intended for **initial disk setup**, not resizing existing partitions

---

## Safety Notes

* **All existing data will be destroyed after you confirm that you want to partition the disk or disk image**
* Double-check:

  * Selected disk
  * Partition sizes
  * Partition type
* When working on Atari systems, **reboot** after the program has finished to apply the new partitioning

---

## atari-mk-hd-image.sh

A _bash_ shell script is included that creates a single partition disk image. The disk image can optionally be filled with content from a directory.

````
Usage: ./atari-mk-hd-image.sh [-msdos] <size> [filename] [contentdir]
````

If no `filename` is specified, the default is `hd.img`. If `-msdos` is specified, an MS-DOS partition table is created, otherwise an Atari partition table is created.

Example:

```
./atari-mk-hd-image.sh 128 disk.img /tmp/tos/
```

Creates a new 128 MiB image `disk.img` and fills it with the contents from the `/tmp/tos` directory.

---

## License

This program is **free software**, distributed under the **GNU General Public License (GPL), version 2 or later**.

You are free to use, modify, and redistribute it under the terms of that license.

Note: As stated in the license terms, this program is provided “AS IS” WITHOUT WARRANTY OF ANY KIND.

---

## Building from source code

This program is written in the [Nim programming language](https://nim-lang.org/). 

To build the TOS version, the `Atari_TOS_support_v2` branch from https://github.com/czietz/Nim/ is required. The exact build steps are documented in the GitHub actions work-flow file `.github/workflows/build.yml` .
