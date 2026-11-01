# Patch for Engine.dll of Shrek 2 (PC): a client keeps its level while it connects to the next one.
#
# ULevel::TickNetClient (Engine.dll, function at RVA 0x136e50) runs every tick of a client level. When the connection to
# the server is closed it puts the travel "?closed" on the viewport. When the host changes the level, that happens while
# the client is already connecting to the new level, and the "?closed" travel cancels the pending connection (the client
# falls back to the default map and never joins). Later the old level has no net driver / no server connection for a
# while and the function reads through them without a check (a crash).
#
# Changes (in place, the size of the file does not change):
#  1. the start of the function checks that the net driver and the server connection exist and skips the rest if not;
#  2. the compare with "closed" (state 1) is followed by a check of UGameEngine+0x13c (the pending level, the field LoadMap
#     compares with its Pending argument): with a pending level the "?closed" travel is skipped.
# The second check is placed in the body of the assert on the error path (unreachable in normal play), reached by a jump.
#
#  3. UGameEngine::Tick (RVA 0x122cb0) no longer ticks the current level while the engine has a pending level: the old
#     client level keeps a pointer to the net driver that the pending connection has already replaced, and ticking it
#     crashes (TickNetClient, UpdateTime, ...). The old level only stays on the screen. The extra test is in a padding
#     area before the function (0x10421800).
#
# usage: patch_engine.py <Engine.dll in> <Engine.dll out>      (the input is never modified)
import sys, struct, hashlib

IMAGE_BASE = 0x10300000
START = 0x10436e90      # MOV EDX,[ECX+0x40] ... JNZ 0x10436ee8 (19 bytes)
CAVE = 0x10436eb0       # the assert call on the error path (21 bytes)
SKIP = 0x10436ee8       # the code after the "?closed" travel
RESUME = 0x10436ea6     # the code after MOV EDX,[ECX+0x44]
ORIG_START = bytes.fromhex('8b5140' '8b423c' '8b4070' '83f803' '744a' '83f801' '7545')
TICK_JZ = 0x10422e3f      # JZ 0x10422fd8 (no current level: skip the level tick); EDX = engine, EDI = 0
TICK_SKIP = 0x10422fd8
TICK_NEXT = 0x10422e45
PAD = 0x10421800          # inside the 0xcc padding 0x104217f0..0x10422cb0
ORIG_TICK_JZ = bytes.fromhex('0f8493010000')
ORIG_CAVE = bytes.fromhex('683d020000' '6808467410' '6818467410' 'ff151c539610')

def rva_to_off(data, va):
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    nsec = struct.unpack_from('<H', data, pe + 6)[0]
    opt = struct.unpack_from('<H', data, pe + 20)[0]
    sec = pe + 24 + opt
    rva = va - IMAGE_BASE
    for i in range(nsec):
        name, vsize, vaddr, rsize, roff = struct.unpack_from('<8sIIII', data, sec + 40 * i)
        if vaddr <= rva < vaddr + max(vsize, rsize):
            return roff + rva - vaddr
    raise SystemExit('address not in a section: %x' % va)

def rel8(next_addr, target):
    d = target - next_addr
    assert -128 <= d <= 127, d
    return struct.pack('<b', d)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = bytearray(open(src, 'rb').read())
    o_start = rva_to_off(data, START)
    o_cave = rva_to_off(data, CAVE)
    if bytes(data[o_start:o_start + len(ORIG_START)]) != ORIG_START or bytes(data[o_cave:o_cave + len(ORIG_CAVE)]) != ORIG_CAVE:
        raise SystemExit('the code does not match the expected Engine.dll (already patched or another build): not patching')

    # the start of the function: net driver and server connection must exist
    a = START
    code = bytearray()
    code += bytes.fromhex('8b5140')                                   # MOV EDX,[ECX+0x40]   net driver
    code += bytes.fromhex('85d2')                                     # TEST EDX,EDX
    code += b'\x74' + rel8(a + len(code) + 2, SKIP)                   # JZ skip
    code += bytes.fromhex('8b523c')                                   # MOV EDX,[EDX+0x3c]   server connection
    code += bytes.fromhex('85d2')                                     # TEST EDX,EDX
    code += b'\x74' + rel8(a + len(code) + 2, SKIP)                   # JZ skip
    jmp_at = a + len(code)
    code += b'\xe9' + struct.pack('<i', CAVE - (jmp_at + 5))          # JMP cave
    assert len(code) <= len(ORIG_START), len(code)
    code += b'\x90' * (len(ORIG_START) - len(code))
    data[o_start:o_start + len(ORIG_START)] = code

    # the cave: connection state 1 (closed) and no pending level -> the original "?closed" travel
    c = CAVE
    cave = bytearray()
    cave += bytes.fromhex('837a7001')                                 # CMP dword [EDX+0x70],1   state of the connection
    cave += b'\x75' + rel8(c + len(cave) + 2, SKIP)                   # JNZ skip
    cave += bytes.fromhex('8b5144')                                   # MOV EDX,[ECX+0x44]   engine
    cave += bytes.fromhex('83ba3c01000000')                           # CMP dword [EDX+0x13c],0   pending level
    cave += b'\x75' + rel8(c + len(cave) + 2, SKIP)                   # JNZ skip
    cave += b'\xeb' + rel8(c + len(cave) + 2, RESUME)                 # JMP resume
    assert len(cave) <= len(ORIG_CAVE), len(cave)
    cave += b'\x90' * (len(ORIG_CAVE) - len(cave))
    data[o_cave:o_cave + len(ORIG_CAVE)] = cave

    # 3. the engine tick
    o_jz = rva_to_off(data, TICK_JZ)
    o_pad = rva_to_off(data, PAD)
    if bytes(data[o_jz:o_jz + 6]) != ORIG_TICK_JZ or any(b != 0xcc for b in data[o_pad:o_pad + 23]):
        raise SystemExit('engine tick code or padding does not match: not patching')
    JZ32 = bytes.fromhex('0f84')
    JNZ32 = bytes.fromhex('0f85')
    JMP32 = bytes.fromhex('e9')
    NOP = bytes.fromhex('90')
    pad = bytearray()
    pad += JZ32 + struct.pack('<i', TICK_SKIP - (PAD + len(pad) + 6))     # JZ skip  (no level)
    pad += bytes.fromhex('39ba3c010000')                                  # CMP [EDX+0x13c],EDI  (pending level)
    pad += JNZ32 + struct.pack('<i', TICK_SKIP - (PAD + len(pad) + 6))    # JNZ skip
    pad += JMP32 + struct.pack('<i', TICK_NEXT - (PAD + len(pad) + 5))    # JMP on
    data[o_pad:o_pad + len(pad)] = pad
    data[o_jz:o_jz + 6] = JMP32 + struct.pack('<i', PAD - (TICK_JZ + 5)) + NOP

    open(dst, 'wb').write(data)
    print('patched %s -> %s' % (src, dst))
    print('sha256 before', hashlib.sha256(open(src, 'rb').read()).hexdigest())
    print('sha256 after ', hashlib.sha256(bytes(data)).hexdigest())

main()
