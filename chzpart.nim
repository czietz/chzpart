# SPDX-License-Identifier: GPL-2.0-or-later

# CHZ Atari Disk Partitioning Tool
#
# Copyright (c) 2025 - 2026 Christian Zietz <czietz@gmx.net>
#

import std/os
import std/strformat
import std/strutils
import std/options
import std/endians
import std/random
import std/assertions

### GLOBAL VARIABLES AND TYPES ###

const ProgramBanner   = "CHZ Atari Disk Partitioning Tool - "
when defined(avoidGit):
    const GitBanner   = "(local)"
else:
    const GitBanner   = staticExec("git describe --tags --always --dirty")
const CopyrightBanner = "(C) 2026 Christian Zietz <czietz@gmx.net>\n" &
                        "This program is free software; you can redistribute it and/or modify\n" &
                        "it under the terms of the GNU General Public License."

type PartitionType = enum TypeDOS, TypeAtari

type TOSSupport = enum TOS100, TOS104, TOS404

const maxSizeTOS = [TOS100: 256, TOS104: 512, TOS404: 1024]

### LIBCMINI / ATARI STUBBING CODE ###

# use disk-image on non-Atari platform
const useDiskImage {.booldefine.}: bool = not defined(atari)

when useDiskImage:
    import std/cmdline

when defined(atari):
    proc Random(): clong {.header: "<osbind.h>".}

# on Atari, we use Cconrs for better line editing
when defined(atari):
    type
        Line {.importc: "_CCONLINE", header: "<osbind.h>".} = object
            maxlen: int
            actuallen: int
            buffer: array[255,char]
    proc Cconrs(line: ptr[Line]) {.importc, header: "<osbind.h>".}
    proc readInputLine(): string =
        var l: Line
        l.maxlen = l.buffer.len
        Cconrs(addr l)
        echo ""
        if l.actuallen>0:
            return substr(l.buffer[0..(l.actuallen-1)])
        else:
            return ""

else:
    proc readInputLine(): string =
        stdin.readLine()

# test if we run under EmuTOS
when defined(atari):

    import std/volatile

    const
        SysBase = 0x4f2
        EtosMagic = 0x45544f53 # _ETOS
    proc Super(val: clong): clong {.header: "<osbind.h>".}
    proc SuperToUser(val: clong)  {.header: "<osbind.h>".}

    proc checkEmuTOS(): bool =
        let old_ssp = Super(0)
        # Use a volatileLoad to make sure that value
        # is really being read between the Super/SuperToUser calls.
        let osheader = volatileLoad(cast[ptr clong](SysBase))
        let rsvd = volatileLoad(cast[ptr clong](osheader+0x2c))
        SuperToUser(old_ssp)
        return (rsvd == EtosMagic)

    # cache result
    proc isEmuTOS(): bool =
        let check {.global.} = checkEmuTOS()
        return check


### XHDI LIBRARY ###

when defined(atari):
    {.compile: "xhdi.c".}

    proc XHGetVersion(): clong {.importc, header: "xhdi.h".}
    proc XHInqTarget(major: cushort, minor: cushort, blksize: ptr[culong], flags: ptr[culong], name: cstring): clong {.importc, header: "xhdi.h".}
    proc XHGetCapacity(major: cushort, minor: cushort, blocks: ptr[culong], blksize: ptr[culong]): clong {.importc, header: "xhdi.h".}
    proc XHReadWrite(major: cushort, minor: cushort, rwflag: cushort, recno: culong, count: cushort, buf: pointer): clong {.importc, header: "xhdi.h".}


### HELPER FUNCTIONS ###

# evaluated at compile-time!
# e.g. converts "ABC" to ['A','B','C']

template toArr(s: static[string]): untyped =
    var arr: array[s.len,char]
    for i in 0 ..< s.len:
        arr[i] = s[i]
    arr


### MENU CODE ###

type
    MenuItem = object
        val: int
        key: char
        text: string
        help: string

proc displayMenu(prompt: string, items: openArray[MenuItem], implicitquit = true): Option[int] =

    while true:
        echo "\n" & prompt & ":"
        for i in items:
            echo fmt"[{i.key}] {i.text}"
            if i.help != "":
                echo "    " & i.help

        if implicitquit:
            echo "[Q] Quit program, discarding changes"

        stdout.write "["
        for i in items:
            stdout.write i.key

        if implicitquit:
            stdout.write "Q"

        stdout.write "] > "
        stdout.flushFile()

        let choice = readInputLine().strip().toUpperAscii()

        for i in items:
            if choice == $(i.key):
                return some(i.val)

        if implicitquit:
            if choice == "Q":
                return  # without return value

        echo fmt"Invalid input '{choice}'"


proc getNumber(prompt: string, min: int, max: int, implicitquit = true): Option[int] =

    while true:
        echo "\n" & prompt & ":"

        stdout.write fmt"[{min}-{max}"

        if implicitquit:
            stdout.write ", Q to quit"

        stdout.write "] > "
        stdout.flushFile()

        let choice = readInputLine().strip().toUpperAscii()

        if implicitquit:
            if choice == "Q":
                return  # without return value

        try:
            let number = choice.parseInt()
            if (number >= min) and (number <= max):
                return some(number)
        except:
            discard

        echo fmt"Invalid input '{choice}'"

### DISK WRITE CODE ###

const SectSize = 512
const SectPerMiB = 1024*1024 div SectSize

type
    Sector = array[SectSize, uint8]

    Partition = object
        start: int
        length: int

var zeroSector: Sector

when useDiskImage:

    proc getDiskSize(unit: int): int =
        # write to file
        let fz = int(getFileSize(paramStr(1)) div SectSize)
        return fz

    proc getDiskName(unit: int): Option[string] =
        # write to file
        some(fmt"Disk image '{paramStr(1)}'")

    proc getAvailableDisks(menu_disk: var seq[MenuItem]) =
        # write to file
        menu_disk.add(MenuItem(val: 0, key: 'A', text: getDiskName(0).get(), help: fmt"Size: {getDiskSize(0) div SectPerMiB} MiB"))

else:   # not useDiskImage

    proc getDiskSize(unit: int): int =
        var blksize: culong
        var blocks: culong
        let retval = XHGetCapacity(cushort(unit), 0, addr blocks, addr blksize)
        if (retval == 0) and (blocks > 0):
            doAssert(blksize == SectSize, "only devices with 512 bytes per sector are supported")
            result = int(blocks) * (int(blksize) div SectSize)
        else:
            result = 0

    proc getDiskName(unit: int): Option[string] =
        var
            blksize: culong
            flags: culong
            name = newString(33)

        let retval = XHInqTarget(cushort(unit), 0, addr blksize, addr flags, name.cstring)
        if (retval == 0) and (blksize > 0):
            return some($(name.cstring))
        else:
            return # none

    proc getAvailableDisks(menu_disk: var seq[MenuItem]) =
        const busnames = ["ACSI", "SCSI", "IDE", "SD-Card", "USB"]
        var
            cnt = 0

        let units = {0..19, 24, 32..39}
        for unit in units:
            let diskName = getDiskName(unit)
            if diskName.isSome:
                let bus = unit div 8
                let dev = unit mod 8
                let siz = getDiskSize(unit) div SectPerMiB
                menu_disk.add(MenuItem(val: unit, key: chr(ord('A')+cnt), text: diskName.get(), help: fmt"Bus: {busnames[bus]}. Device: {dev}. Size: {siz} MiB"))
                cnt = cnt+1


proc diskWrite(unit: int, sectNum: int, sectData: Sector, byteswap: bool, partition: Option[Partition] = none(Partition)) =

    var realSectNum: int
    if partition.isSome:
        let part = partition.get()
        realSectNum = sectNum + part.start
        doAssert(sectNum < part.length, "attempted to write outside of partition")
    else:
        realSectNum = sectNum

    # swap out of place in order not to corrupt passed data
    var realSectData = sectData
    if byteswap:
        for k in countup(0, SectSize-1, 2):
            let temp = realSectData[k]
            realSectData[k] = realSectData[k+1]
            realSectData[k+1] = temp

    when useDiskImage:
        # write to file
        let tmpFile = open(paramStr(1), mode = fmReadWriteExisting)
        tmpFile.setFilePos(realSectNum * SectSize)
        let numWritten = tmpFile.writeBuffer(addr realSectData, SectSize)
        if numWritten != SectSize:
            raise newException(IOError, "could not write to file")
        tmpFile.close()
    else: # not useDiskImage
        # on EmuTOS one can bypass potential additional byte-swapping by the disk driver
        let rwflag = (if isEmuTOS(): (0x80 + 1) else: 1)
        let retval = XHReadWrite(cushort(unit), 0, cushort(rwflag), culong(realSectNum), 1, addr realSectData)
        if retval != 0:
            raise newException(IOError, "could not write to disk")

### PARTITON TABLE CODE ###

type
    DOSPart {.packed.} = object
        bootable:   uint8 = 0
        chs_start:  array[3,uint8]
        part_type:  uint8 = 0
        chs_end:    array[3,uint8]
        lba_start:  uint32
        lba_size:   uint32

    DOSMBR {.packed.} = object
        filler1:    array[440,uint8]
        signature:  uint32
        filler2:    uint16 = 0
        parttable:  array[4,DOSPart]
        magic:      array[2,uint8] = [0x55, 0xaa]

    AtariPart {.packed.} = object
        active:     uint8 = 0
        part_type:  array[3,char]
        lba_start:  uint32
        lba_size:   uint32

    AtariMBR {.packed.} = object
        filler1:    array[448,uint8]
        checksum:   uint16
        disk_size:  uint32
        parttable:  array[4,AtariPart]
        badsect:    uint32  # not used
        badsize:    uint32  # not used
        filler2:    uint16

# convert a LBA to CHS, using an assumed fake geometry
# Atari does not care about CHS, but some disk editing tools might complain
# if the CHS values don't look sensible
const CHSSectorsPerTrack = 63 # maximum permitted value
const CHSNumberOfHeads = 256 # maximum permitted value
func LBA2CHS(lba: int): array[3,uint8] =
    let Temp = lba div CHSSectorsPerTrack
    let Sector = (lba mod CHSSectorsPerTrack) + 1
    let Head = Temp mod CHSNumberOfHeads
    let Cylinder = Temp div CHSNumberOfHeads

    if Cylinder <= 1023: # maximum permitted value
        # encode it for MBR (PC BIOS INT13h)
        result = [uint8(Head),uint8(((Cylinder div 256) shl 6) or Sector),uint8(Cylinder mod 256)]
    else:
        result = [0xff,0xff,0xff] # cannot be represented as CHS

type
    DOSPart_Type = uint8
const
    DOSPart_FAT16: DOSPart_Type = 0x06
    DOSPart_Extended: DOSPart_Type = 0x05

func fillDOSPart(p: var DOSPart, start: int, length: int, parttype = DOSPart_FAT16) =
    p.part_type = parttype
    p.lba_start = uint32(start)
    p.lba_size = uint32(length)
    littleEndian32(addr p.lba_start, addr p.lba_start)
    littleEndian32(addr p.lba_size, addr p.lba_size)
    p.chs_start = LBA2CHS(start)
    p.chs_end = LBA2CHS(start+length-1)

type AtariPart_Type = array[3,char]
const
    AtariPart_FAT16: AtariPart_Type = ['B','G','M']
    AtariPart_FAT16_small: AtariPart_Type = ['G','E','M']   # less than 16 MB
    AtariPart_Extended: AtariPart_Type = ['X','G','M']

func fillAtariPart(p: var AtariPart, start: int, length: int, parttype = AtariPart_FAT16) =
    p.active = 1
    p.part_type = parttype
    if (length < 16*SectPerMiB) and (parttype == AtariPart_FAT16):
        p.part_type = AtariPart_FAT16_small

    p.lba_start = uint32(start)
    p.lba_size = uint32(length)
    bigEndian32(addr p.lba_start, addr p.lba_start)
    bigEndian32(addr p.lba_size, addr p.lba_size)

proc createMBR(unit: int, parts: var openArray[Partition], diskSize: int, tos: Option[TOSSupport], byteswap: bool) =

    var MBR: Sector

    # whether to create Atari or DOS MBR
    let atari = tos.isSome()

    # when more than 4 partitions are requested, create extended partitions
    let numParts = parts.len
    let doExtended = numParts > 4
    let numPrimary = (if doExtended: 3 else: numParts)

    # Create MBR with primary partitions
    if not atari:
        # DOS-style
        var m = DOSMBR()
        m.signature = rand(uint32)    # don't bother with endianness
        for k in 0 ..< numPrimary:
            fillDOSPart(m.parttable[k], start=parts[k].start, length=parts[k].length)
        if doExtended:
            # spans the entire remaining length of the disk
            fillDOSPart(m.parttable[3], start=parts[3].start, length=diskSize - parts[3].start,
                        parttype=DOSPart_Extended)

        MBR = cast[Sector](m)
    else:
        # Atari-style
        var m = AtariMBR()
        m.disk_size = uint32(diskSize)
        bigEndian32(addr m.disk_size, addr m.disk_size)
        for k in 0 ..< numPrimary:
            fillAtariPart(m.parttable[k], start=parts[k].start, length=parts[k].length)
        if doExtended:
            # spans the entire remaining length of the disk
            fillAtariPart(m.parttable[3], start=parts[3].start, length=diskSize - parts[3].start,
                          parttype=AtariPart_Extended)

        # calculate checksum so that MBR is NOT bootable
        let MBR2 = cast[array[256,uint16]](m)
        var sum: uint16 = 0
        for k in MBR2:
            var word: uint16
            bigEndian16(addr word, addr k)
            sum = sum + word
        m.checksum = 0xFFFF'u16 - sum   # 0x1234 would make it bootable
        bigEndian16(addr m.checksum, addr m.checksum)

        MBR = cast[Sector](m)

    diskWrite(unit, 0, MBR, byteswap)

    # Create extended boot records with extended partitions
    if doExtended:
        # location of first extended boot record
        let extendedStart = parts[3].start

        for k in 3 ..< numParts:
            let extendedCurrent = parts[k].start
            # fixup partitions to make space for extended boot record
            parts[k].start = parts[k].start+1
            parts[k].length = parts[k].length-1

            if not atari:
                var m = DOSMBR()

                # start is relative to this boot record
                fillDOSPart(m.parttable[0], start=1, length=parts[k].length)

                if k < numParts-1:
                    # another extended partition follows?
                    fillDOSPart(m.parttable[1], start=parts[k+1].start - extendedStart, # relative to the first extended boot record!
                                                length=diskSize - parts[k+1].start, # spans remaining length of disk
                                                parttype=DOSPart_Extended)

                MBR = cast[Sector](m)

            else: # atari
                # Atari-style
                var m = AtariMBR()

                fillAtariPart(m.parttable[0], start=1, length=parts[k].length)

                if k < numParts-1:
                    # another extended partition follows?
                    fillAtariPart(m.parttable[1], start=parts[k+1].start - extendedStart, # relative to the first extended boot record!
                                                  length=diskSize - parts[k+1].start, # spans remaining length of disk
                                                  parttype=AtariPart_Extended)

                MBR = cast[Sector](m)

            diskWrite(unit, extendedCurrent, MBR, byteswap)

### FAT FILE SYSTEM CODE ###

type
    FATBoot {.packed.} = object
        bootjmp:    array[3,uint8] = [0xeb, 0x3c, 0x90]
        oemname:    array[8,char] = toArr("CHZPT5.0")
        bps:        uint16 = SectSize
        spc:        uint8
        reserved:   uint16 = 1
        numfat:     uint8 = 2
        numroot:    uint16 = 256
        numsect:    uint16 = 0
        mediatype:  uint8 = 0xF8
        spf:        uint16
        spt:        uint16 = CHSSectorsPerTrack
        numhead:    uint16 = CHSNumberOfHeads-1
        hidden32:   uint32
        numsect32:  uint32 = 0
        disknum:    uint8 = 0x80
        dirty:      uint8 = 0
        extsig:     uint8 = 0x29
        volid32:    uint32
        volname:    array[11,char] = toArr("NO NAME    ")
        fstype:     array[8,char] = toArr("FAT16   ")
        filler:     array[448,uint8]
        magic:      array[2,uint8] = [0x55, 0xaa]

proc createFAT16(unit:int, part: Partition, tos: Option[TOSSupport], byteswap: bool) =

    # whether to create Atari-compatible file system
    let atari = tos.isSome()

    var b = FATBoot()

    # find the smallest cluster size that results in max amount of clusters
    var clustersize = 2
    let maxclusters = if atari:
                        (case tos.get():
                            of TOS100:
                                16382
                            of TOS104, TOS404:
                                32766
                        )
                      else: 65524 # according to MS FAT spec

    while part.length div clustersize > maxclusters:
        clustersize = clustersize shl 1

    # fill in sector and cluster size
    var logsec = 1
    if atari:
        # Atari style: larger logical sectors
        b.spc = 2
        logsec = clustersize div 2
        b.bps = uint16(logsec * SectSize)
    else:
        # MS-DOS style: larger sector-per-cluster number
        b.spc = uint8(clustersize)

    # fill in total number of sectors
    let partsect = part.length div logsec
    if partsect < 65536:
        b.numsect = uint16(partsect)
    else:
        b.numsect32 = uint32(partsect)

    # fill in hidden sectors (physical! sectors before partition start)
    b.hidden32 = uint32(part.start)

    # FAT size calculation in physical! sectors (formulas taken from MS FAT spec)
    let rootdirsect = ((int(b.numroot) * 32) + (SectSize - 1)) div SectSize
    let tmpval1 = part.length - int(b.reserved) - rootdirsect
    let tmpval2 = (256 * clustersize) + int(b.numfat) # TODO: check why + numfat ?
    let fatsz = (tmpval1 + (tmpval2-1)) div tmpval2
    b.spf = uint16(fatsz)

    # fixup for Atari
    if atari:
        b.spf = uint16((fatsz + (logsec-1)) div logsec)

    # TODO: fill volume ID according to spec with creation date
    b.volid32 = rand(uint32)

    # safety check
    if not atari:
        doAssert(b.numfat == 2, "invalid number of FATs")
        doAssert((logsec == 1) and (int(b.bps) == 512), "invalid logical sector size")
        doAssert(clustersize <= 64, "invalid cluster size")
    else:
        doAssert(b.numfat == 2, "invalid number of FATs")
        doAssert(b.spc == 2, "invalid number of sectors per cluster")
        if tos.get() == TOS404:
            doAssert(logsec <= 32, "logical sector size too large")
        else:
            doAssert(logsec <= 16, "logical sector size too large")
        doAssert(b.numsect32 == 0, "Atari partition with more than 65535 log. sectors")
        doAssert(int(b.numroot) <= 1008, "root directory too large")

    # create FATs in physical sectors
    var fat: Sector
    let realfatsz = int(b.spf) * logsec
    let fat1start = int(b.reserved) * logsec
    let fat2start = fat1start + realfatsz
    var rootdirstart = fat2start # updated later!
    fat[0] = b.mediatype
    fat[1] = 0xff
    fat[2] = 0xff
    fat[3] = 0xff
    diskWrite(unit, fat1start, fat, byteswap, some(part))
    for k in 1 ..< realfatsz:
        diskWrite(unit, fat1start+k, zeroSector, byteswap, some(part))
    if b.numfat == 2:
        rootdirstart = fat2start + realfatsz
        diskWrite(unit, fat2start, fat, byteswap, some(part))
        for k in 1 ..< realfatsz:
            diskWrite(unit, fat2start+k, zeroSector, byteswap,some(part))

    # zero root directory
    for k in 0 ..< rootdirsect:
        diskWrite(unit, rootdirstart+k, zeroSector, byteswap, some(part))

    # convert all fields to littleEndian
    littleEndian16(addr b.bps, addr b.bps)
    littleEndian16(addr b.reserved, addr b.reserved)
    littleEndian16(addr b.numroot, addr b.numroot)
    littleEndian16(addr b.numsect, addr b.numsect)
    littleEndian16(addr b.spf, addr b.spf)
    littleEndian16(addr b.spt, addr b.spt)
    littleEndian16(addr b.numhead, addr b.numhead)

    littleEndian32(addr b.hidden32, addr b.hidden32)
    littleEndian32(addr b.numsect32, addr b.numsect32)
    littleEndian32(addr b.volid32, addr b.volid32)

    # write boot sectors
    let s = cast[Sector](b)
    diskWrite(unit, 0, s, byteswap, some(part))

### MAIN FUNCTION CODE ###

echo ProgramBanner & GitBanner
echo CopyrightBanner
echo ""

when defined(atari):
    # use XBIOS random generator to seed Nim random generator
    randomize(Random())
else:
    randomize()

when useDiskImage:
    #  Write to file
    if paramCount() < 1:
        let exename = splitPath(getAppFilename()).tail
        echo "Usage:"
        echo fmt"To use an existing image: {exename} disk_image.img"
        echo fmt"To create a new image:    {exename} disk_image.img size_in_MiB"
        quit(1)

    if paramCount() == 1:
        if not fileExists(paramStr(1)):
            echo fmt"Cannot open disk image file '{paramStr(1)}'!"
            quit(1)

    if paramCount() > 1:
        if fileExists(paramStr(1)):
            echo fmt"Disk image file '{paramStr(1)}' already exists!"
            quit(1)

        # write to file
        var fileSize: int
        try:
            fileSize = parseInt(paramStr(2)) * 1024*1024
        except ValueError:
            echo fmt"Illegal size '{paramStr(2)}'!"
            quit(1)

        let tmpFile = open(paramStr(1), mode = fmWrite)
        tmpFile.setFilePos(fileSize - SectSize)
        let numWritten = tmpFile.writeBuffer(addr zeroSector, SectSize)
        if numWritten != SectSize:
            raise newException(IOError, "could not write to file")
        tmpFile.close()

when not useDiskImage:
    # Check XHDI is available
    let xhdiver = XHGetVersion()
    if xhdiver < 0x110:
        echo "XHDI is required!"
        echo "XHDI is available, e.g., under EmuTOS PRG and ROMs sized 256k and above."
        echo "Press Enter to exit."
        discard readInputLine()
        quit(1)

var menu_disk: seq[MenuItem]
getAvailableDisks(menu_disk)

if menu_disk.len == 0:
    echo "No hard disks found!"
    echo "Press Enter to exit."
    discard readInputLine()
    quit(1)

let unitChoice = displayMenu("Select hard disk", menu_disk)
if unitChoice.isNone:
    quit(1)
let unit = unitChoice.get()

# menu and mapping must be in the same order!
let menu_mapping = [(TypeDOS, none(TOSSupport)), # 0
                    (TypeAtari, some(TOS104)),   # 1
                    (TypeAtari, some(TOS100)),   # 2
                    (TypeAtari, some(TOS404))]   # 3
let menu_type =  [MenuItem(val: 0, key: 'M', text: "MS-DOS", help: "Compatible with EmuTOS, Windows, Linux, macOS"),
                  MenuItem(val: 1, key: 'A', text: "Atari TOS >= 1.04", help: "Compatible with EmuTOS, Atari TOS 1.04 and above"),
                  MenuItem(val: 2, key: 'B', text: "Atari TOS >= 1.00", help: "Compatible with EmuTOS, Atari TOS (all versions)"),
                  MenuItem(val: 3, key: 'C', text: "Atari TOS >= 4.04", help: "Compatible with EmuTOS, Atari TOS 4.04 only")]

let partChoice = displayMenu("Select partition type", menu_type)
if partChoice.isNone:
    quit(1)

let (partType,tosType) = menu_mapping[partChoice.get()]

# under EmuTOS one can control byte-swapping by the disk driver during XHReadWrite
# ... so the byte-swapping is entirely under control of this program and one can
# ... ask the user (in case of IDE disks) if they like byte-swapping or not
var swapBytes = false
when not useDiskImage:
    let bus = unit div 8
    if isEmuTOS() and (partType == TypeDOS) and (bus == 2): # IDE bus
        let menu_swap =  [MenuItem(val: int(true), key: 'Y', text: "Activate byte swapping", help: "On 'dumb' IDE interfaces, this facilitates data exchange"),
                          MenuItem(val: int(false), key: 'N', text: "Deactivate byte swapping", help: "Recommended for best performance")]
        let swapChoice = displayMenu("IDE byte-swapping", menu_swap)
        if swapChoice.isNone:
            quit(1)
        swapBytes = bool(swapChoice.get())

let numChoice = getNumber("Number of partitions", 1, 14)
if numChoice.isNone:
    quit(1)
let numPart = numChoice.get()

let diskName = getDiskName(unit).get()
let diskSize = getDiskSize(unit)

# Ask the user for partition sizes
var startPart = 1 # first sector is for MBR
var parts: seq[Partition]
for k in 1..numPart:
    const partWords = ["1st","2nd","3rd"]
    const minSize = 5 # to avoid disks with less than 4085 clusters

    # maximum size for this partition
    var maxSize = ((diskSize - startPart) div SectPerMiB) - (minSize * (numPart-k))
    if (partType == TypeAtari) and (maxSize > maxSizeTOS[tosType.get()]):
        maxSize = maxSizeTOS[tosType.get()]
    if (partType == TypeDOS) and (maxSize > 2047):
        maxSize = 2047

    let partWord = (if k <= 3: partWords[k-1] else: $k & "th")
    let sizeChoice = getNumber("Size of " & partWord & " partition in MiB", minSize, maxSize)
    if sizeChoice.isNone:
        quit(1)
    var sizeSect = sizeChoice.get() * SectPerMiB

    if (partType == TypeAtari) and (sizeChoice.get() == maxSizeTOS[tosType.get()]):
        # a TOS partition can have max. 64 sectors per cluster
        # need to subtract two clusters to reach the absolute maximum size
        sizeSect = sizeSect - 128

    let part = Partition(start: startPart, length: sizeSect)
    parts.add(part)
    startPart = startPart + sizeSect

# Ask the user to confirm partition creation
let menu_confirm =  [MenuItem(val: int(true), key: 'Y', text: "Partition: " & diskName, help: "This deletes the existing disk content!"),
                     MenuItem(val: int(false), key: 'N', text: "Discard changes and exit program")]
let confirmChoice = displayMenu("Confirm disk partitioning", menu_confirm, implicitquit = false)
if confirmChoice.isNone or not bool(confirmChoice.get()):
    quit(0)

stdout.write "Partitioning disk... "
stdout.flushFile()

# Partiton the disk and create file systems
createMBR(unit, parts, diskSize, tosType, swapBytes)
for part in parts:
    createFAT16(unit, part, tosType, swapBytes)

echo "done!"

when not useDiskImage:
    echo "*** Reboot your system NOW! ***"
    discard readInputLine()
