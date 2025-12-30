LIBCMINI=/home/czietz/libcmini-mintelf /tmp/Nim_v2/bin/nim c --cpu:m68k --os:atari --out:chzpart.tos -d:libcmini -d:mintelf -d:release chzpart.nim
# LIBCMINI=/home/czietz/libcmini-mintelf /tmp/Nim_v2/bin/nim c --cpu:m68k --os:atari --out:chzpimg.ttp -d:mintelf -d:release -d:useDiskImage=true chzpart.nim
/tmp/Nim_v2/bin/nim c -d:release chzpart.nim
/tmp/Nim_v2/bin/nim c -d:mingw -d:release chzpart.nim
