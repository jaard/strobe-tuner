// PortAudio ring-buffer bindings, kept here so the C ABI matches every target.
package pa_ringbuffer

// Only used on non-Apple targets.
@(require) import "core:c"

when ODIN_OS == .Windows {
    foreign import lib "../../external/portaudio/pa_ringbuffer.lib"
} else {
    foreign import lib "../../external/portaudio/pa_ringbuffer.a"
}

// pa_ringbuffer.h uses int32_t on Apple and C long elsewhere. In particular, long is
// 64-bit on Android/Linux ARM64, but 32-bit on Windows, even in a 64-bit process.
when ODIN_OS == .Darwin {
    Size :: i32
} else {
    Size :: c.long
}

RingBuffer :: struct {
    bufferSize:       Size,
    writeIndex:       Size,
    readIndex:        Size,
    bigMask:          Size,
    smallMask:        Size,
    elementSizeBytes: Size,
    buffer:           ^u8,
}

@(default_calling_convention = "c", link_prefix = "PaUtil_")
foreign lib {
    InitializeRingBuffer :: proc(rbuf: ^RingBuffer, element_size: Size, count: Size, data: rawptr) -> Size ---
    FlushRingBuffer :: proc(rbuf: ^RingBuffer) ---
    GetRingBufferReadAvailable :: proc(rbuf: ^RingBuffer) -> Size ---
    WriteRingBuffer :: proc(rbuf: ^RingBuffer, data: rawptr, count: Size) -> Size ---
    ReadRingBuffer :: proc(rbuf: ^RingBuffer, data: rawptr, count: Size) -> Size ---
    AdvanceRingBufferReadIndex :: proc(rbuf: ^RingBuffer, count: Size) -> Size ---
}
