
pub struct Buffer<CAPACITY: u32> {
  data: bits[CAPACITY],
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
    content: (data as bits[CAPACITY] << buffer.length) | buffer.data,
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
    (buffer_append_unsafe(buffer, data), true)
  }
}

pub fn buffer_pop_unsafe<CAPACITY: u32>(
  buffer: Buffer<CAPACITY>, length: u32
) -> (Buffer<CAPACITY>, bits[CAPACITY]) {
  let mask = (bits[CAPACITY]:1 << length) - bits[CAPACITY]:1;
  (
    Buffer {
      content: buffer.data >> length,
      length: buffer.length - length
    },
    buffer.data & mask
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
