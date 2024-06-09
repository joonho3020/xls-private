
import xls.modules.snappy.common;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;

pub struct Buffer<CAPACITY: u32> {
  content: bits[CAPACITY],
  length: u32
}

pub enum BufferStatus : u2 {
  OK = 0,
  FAILED = 1,
}

pub struct BufferResult<CAPACITY: u32> {
  buffer: Buffer<CAPACITY>,
  status: BufferStatus
}

pub fn buffer_can_fit<DSIZE: u32, CAPACITY: u32>(buffer: Buffer<CAPACITY>, data: bits[DSIZE]) -> bool {
  buffer.length + DSIZE <= CAPACITY
}

pub fn buffer_has_at_least<CAPACITY: u32>(buffer: Buffer<CAPACITY>, length: u32) -> bool {
  buffer.length >= length
}

pub fn buffer_append_unsafe<DSIZE: u32, CAPACITY: u32>(
  buffer: Buffer<CAPACITY>, data: bits[DSIZE]
) -> Buffer<CAPACITY> {
  Buffer {
    content: (data as bits[CAPACITY] << buffer.length) | buffer.content,
    length: buffer.length + DSIZE
  }
}

pub fn buffer_append<DSIZE: u32, CAPACITY: u32>(
  buffer: Buffer<CAPACITY>, data: bits[DSIZE]
) -> BufferResult<CAPACITY> {
  if buffer_can_fit(buffer, data) == false {
    BufferResult {
      buffer: buffer,
      status: BufferStatus::FAILED
    }
  } else {
    let buffer = buffer_append_unsafe(buffer, data);
    BufferResult {
      buffer: buffer,
      status: BufferStatus::OK
    }
  }
}

pub fn buffer_pop_unsafe<CAPACITY: u32>(
  buffer: Buffer<CAPACITY>, length: u32
) -> (Buffer<CAPACITY>, bits[CAPACITY]) {
  let mask = (bits[CAPACITY]:1 << length) - bits[CAPACITY]:1;
  (
    Buffer {
      content: buffer.content >> length,
      length: buffer.length - length
    },
    buffer.content & mask
  )
}

pub fn buffer_pop<CAPACITY: u32>(
  buffer: Buffer<CAPACITY>, length: u32
) -> (BufferResult<CAPACITY>, bits[CAPACITY]) {
  if buffer_has_at_least(buffer, length) == false {
    (
      BufferResult {
        buffer: buffer,
        status: BufferStatus::FAILED
      },
      bits[CAPACITY]:0
    )
  } else {
    let (nb, data) = buffer_pop_unsafe(buffer, length);
    (
      BufferResult {
        buffer: nb,
        status: BufferStatus::OK
      },
      data
    )
  }
}

#[test]
fn test_buffer_has_at_least() {
    let buffer = Buffer { content: u32:0, length: u32:0 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), false);
    assert_eq(buffer_has_at_least(buffer, u32:32), false);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);

    trace_fmt!("Hello");

    let buffer = Buffer { content: u32:0, length: u32:16 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), true);
    assert_eq(buffer_has_at_least(buffer, u32:32), false);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);

    let buffer = Buffer { content: u32:0, length: u32:32 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), true);
    assert_eq(buffer_has_at_least(buffer, u32:32), true);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);
}

pub struct RotBuffer<CAPACITY: u32> {
  content: bits[CAPACITY],
  received_so_far_bytes: u32,
  sent_so_far_bytes: u32,
  received_last_chunk: bool
}

pub struct RotBufferResult<CAPACITY: u32> {
  rotbuffer: RotBuffer<CAPACITY>,
  status: BufferStatus
}

pub fn rotbuf_valid_bytes<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>
) -> u32 {
  rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes
}

pub fn rotbuf_is_last_chunk<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>,
  bus_bits: u32
) -> bool {
  let valid_bytes = rotbuf_valid_bytes(rotbuffer);
  let bus_bytes = bus_bits >> 3;
  rotbuffer.received_last_chunk && (valid_bytes <= bus_bytes)
}

pub fn rotbuf_can_fit<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, input_size_bytes: u32
) -> bool {
  let free_bytes = (CAPACITY >> 3) - rotbuf_valid_bytes(rotbuffer);
  free_bytes >= input_size_bytes
}

pub fn rotbuf_append_unsafe<BUS_BITS: u32, CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, databundle: common::DataBundle<BUS_BITS>
) -> RotBuffer<CAPACITY> {
  let rotbuffer_bits = (rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes) << 3;
  RotBuffer {
    content: (databundle.data as bits[CAPACITY] << rotbuffer_bits) | rotbuffer.content,
    received_so_far_bytes: rotbuffer.received_so_far_bytes + databundle.valid_bytes,
    received_last_chunk: databundle.is_last,
    ..rotbuffer
  }
}

pub fn rotbuf_append<BUS_BITS: u32, CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, databundle: common::DataBundle<BUS_BITS>
) -> RotBufferResult<CAPACITY> {
  if rotbuf_can_fit(rotbuffer, databundle.valid_bytes) == false {
    RotBufferResult {
      rotbuffer: rotbuffer,
      status: BufferStatus::FAILED
    }
  } else {
    RotBufferResult {
      rotbuffer: rotbuf_append_unsafe(rotbuffer, databundle),
      status: BufferStatus::OK
    }
  }
}

pub fn rotbuf_has_at_least<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, output_size_bytes: u32
) -> bool {
  let valid_bytes = rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes;
  valid_bytes >= output_size_bytes
}

pub fn rotbuf_peek_unsafe<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, bytes_to_peek: u32
) -> bits[CAPACITY] {
  let bits_to_peek  = bytes_to_peek << 3;
  let mask = (bits[CAPACITY]:1 << bits_to_peek as bits[CAPACITY]) - bits[CAPACITY]:1;
  rotbuffer.content & mask
}

pub fn rotbuf_peek<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, bytes_to_peek: u32
) -> (bool, bits[CAPACITY]) {
  if rotbuf_has_at_least(rotbuffer, bytes_to_peek) == false{
    (false, zero!<bits[CAPACITY]>())
  } else {
    let bits_to_peek  = bytes_to_peek << 3;
    let mask = (bits[CAPACITY]:1 << bits_to_peek as bits[CAPACITY]) - bits[CAPACITY]:1;
    (true, rotbuffer.content & mask)
  }
}

pub fn rotbuf_pop_unsafe<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, bytes_to_pop: u32
) -> (RotBuffer<CAPACITY>, bits[CAPACITY]) {
  let bits_to_pop = bytes_to_pop << 3;
  let mask = (bits[CAPACITY]:1 << bits_to_pop as bits[CAPACITY]) - bits[CAPACITY]:1;
  (
    RotBuffer {
      content: rotbuffer.content >> bits_to_pop,
      sent_so_far_bytes: rotbuffer.sent_so_far_bytes + bytes_to_pop,
      ..rotbuffer
    },
    rotbuf_peek_unsafe(rotbuffer, bytes_to_pop)
  )
}

pub fn rotbuf_pop<CAPACITY: u32>(
  rotbuffer: RotBuffer<CAPACITY>, bytes_to_pop: u32
) -> (RotBufferResult<CAPACITY>, bits[CAPACITY]) {
  if rotbuf_has_at_least(rotbuffer, bytes_to_pop) == false {
    (
      RotBufferResult {
        rotbuffer: rotbuffer,
        status: BufferStatus::FAILED
      },
      bits[CAPACITY]:0
    )
  } else {
    let (nb, data) = rotbuf_pop_unsafe(rotbuffer, bytes_to_pop);
    (
      RotBufferResult {
        rotbuffer: nb,
        status: BufferStatus::OK
      },
      data
    )
  }
}
