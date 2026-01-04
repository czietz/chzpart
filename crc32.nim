# inspired from https://rosettacode.org/wiki/CRC-32#Nim

type TCrc32* = uint32
const InitValue = TCrc32(0xffffffff)

proc createCrcTable(): array[0..255, TCrc32] {.compileTime.} =
    for i in 0..255:
        var rem = TCrc32(i)
        for j in 0..7:
            if (rem and 1) > 0: rem = (rem shr 1) xor TCrc32(0xedb88320)
            else: rem = rem shr 1
        result[i] = rem

# Table created at compile time
const crc32table = createCrcTable()

var runningCrc32: TCrc32

proc initCrc32*() =
    runningCrc32 = InitValue

proc calcCrc32*(x: openArray[uint8], len: int = x.len): TCrc32 =
  result = runningCrc32 # from previous calculations
  for k in 0..(len-1):
    result = (result shr 8) xor crc32table[(result and 0xff) xor x[k]]
  runningCrc32 = result # store for later calculations
  result = not result   # final XOR
