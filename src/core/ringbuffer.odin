// Copyright (C) 2025  Davorin Šego

// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
// more details.

// You should have received a copy of the GNU General Public License along
// with this program.  If not, see <http://www.gnu.org/licenses/>.


package core

import "core:slice"
import "core:testing"

import pa_rb "../pa_ringbuffer"


/* -------------------------------------------------------------------------------------------------

    A shallow wrapper around the PortAudio ringbuffer implementation

------------------------------------------------------------------------------------------------- */


RingBuffer :: pa_rb.RingBuffer


init_ringbuffer :: proc(size: int) -> (RingBuffer, []u8) {
    ringbuffer := RingBuffer{}
    data := make([]u8, size * size_of(f32))
    pa_rb.InitializeRingBuffer(&ringbuffer, pa_rb.Size(size_of(f32)), pa_rb.Size(size), raw_data(data))
    return ringbuffer, data
}


skip_ringbuffer :: proc(self: ^RingBuffer, frame_count: i32) {
    pa_rb.AdvanceRingBufferReadIndex(self, pa_rb.Size(frame_count))
}

ringbuffer_available :: proc(self: ^RingBuffer) -> i32 {
    return i32(pa_rb.GetRingBufferReadAvailable(self))
}

flush_ringbuffer :: proc(self: ^RingBuffer) {
    pa_rb.FlushRingBuffer(self)
}

// Writes as much as fits, returns how many frames were written
write_ringbuffer :: proc(self: ^RingBuffer, input: []f32) -> int {
    return int(pa_rb.WriteRingBuffer(self, raw_data(input), pa_rb.Size(len(input))))
}

// Fills the buffer, or as much of it as there is, returns how many frames were read
read_ringbuffer :: proc(self: ^RingBuffer, buffer: []f32) -> int {
    return int(pa_rb.ReadRingBuffer(self, raw_data(buffer), pa_rb.Size(len(buffer))))
}


@(test)
test_ringbuffer_wrap_and_capacity :: proc(t: ^testing.T) {
    ringbuffer, data := init_ringbuffer(8)
    defer delete(data)

    input := [?]f32{0, 1, 2, 3, 4, 5}
    testing.expect_value(t, write_ringbuffer(&ringbuffer, input[:]), 6)

    first: [4]f32
    testing.expect_value(t, read_ringbuffer(&ringbuffer, first[:]), 4)
    testing.expect(t, slice.equal(first[:], input[:4]))

    // The write crosses the end of the allocation and fills every remaining slot.
    more := [?]f32{6, 7, 8, 9, 10, 11, 12}
    testing.expect_value(t, write_ringbuffer(&ringbuffer, more[:]), 6)
    testing.expect_value(t, ringbuffer_available(&ringbuffer), 8)
    testing.expect_value(t, write_ringbuffer(&ringbuffer, more[:1]), 0)

    output: [10]f32
    slice.fill(output[:], -1)
    testing.expect_value(t, read_ringbuffer(&ringbuffer, output[:]), 8)
    expected := [?]f32{4, 5, 6, 7, 8, 9, 10, 11, -1, -1}
    testing.expect(t, slice.equal(output[:], expected[:]))
    testing.expect_value(t, ringbuffer_available(&ringbuffer), 0)
}

@(test)
test_ringbuffer_skip_and_flush :: proc(t: ^testing.T) {
    ringbuffer, data := init_ringbuffer(8)
    defer delete(data)

    input := [?]f32{1, 2, 3, 4}
    testing.expect_value(t, write_ringbuffer(&ringbuffer, input[:]), 4)
    skip_ringbuffer(&ringbuffer, 3)
    testing.expect_value(t, ringbuffer_available(&ringbuffer), 1)

    output: [1]f32
    testing.expect_value(t, read_ringbuffer(&ringbuffer, output[:]), 1)
    testing.expect_value(t, output[0], 4)

    testing.expect_value(t, write_ringbuffer(&ringbuffer, input[:]), 4)
    flush_ringbuffer(&ringbuffer)
    testing.expect_value(t, ringbuffer_available(&ringbuffer), 0)
    testing.expect_value(t, read_ringbuffer(&ringbuffer, output[:]), 0)

    testing.expect_value(t, write_ringbuffer(&ringbuffer, input[:1]), 1)
    testing.expect_value(t, read_ringbuffer(&ringbuffer, output[:]), 1)
    testing.expect_value(t, output[0], 1)
}
