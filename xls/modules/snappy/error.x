
import std;

// Behavior of reads and writes to the same address in the same "tick".
enum SimultaneousReadWriteBehavior : u2 {
  // The read shows the contents at the address before the write.
  READ_BEFORE_WRITE = 0,
  // The read shows the contents at the address after the write.
  WRITE_BEFORE_READ = 1,
  // Reading an address that is being written in the same tick causes an
  // assertion failure.
  ASSERT_NO_CONFLICT = 2,
}

// Abstract RAM requests and responses (arbitrary ports, options, etc.)
// Can be lowered to concrete RAM requests and responses, e.g. single-port RAM.
//
// Read: (address, mask) -> (data)
pub struct ReadReq<ADDR_WIDTH:u32, NUM_PARTITIONS:u32> {
  addr: bits[ADDR_WIDTH],
  mask: bits[NUM_PARTITIONS],
}
pub struct ReadResp<DATA_WIDTH:u32> {
  data: bits[DATA_WIDTH],
}

// Write: (address, data, mask) -> ()
pub struct WriteReq<ADDR_WIDTH:u32, DATA_WIDTH:u32, NUM_PARTITIONS:u32> {
  addr: bits[ADDR_WIDTH],
  data: bits[DATA_WIDTH],
  mask: bits[NUM_PARTITIONS],
}
pub struct WriteResp {}

pub fn WriteWordReq<NUM_PARTITIONS:u32, ADDR_WIDTH:u32, DATA_WIDTH:u32>(
  addr:uN[ADDR_WIDTH], data:uN[DATA_WIDTH]) ->
   WriteReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS> {
  WriteReq {
        addr: addr,
        data: data,
        mask: std::unsigned_max_value<NUM_PARTITIONS>(),
      }
}

pub fn ReadWordReq<NUM_PARTITIONS:u32, ADDR_WIDTH:u32>(addr:uN[ADDR_WIDTH]) ->
 ReadReq<ADDR_WIDTH, NUM_PARTITIONS> {
  ReadReq<ADDR_WIDTH, NUM_PARTITIONS> {
    addr: addr,
    mask: std::unsigned_max_value<NUM_PARTITIONS>(),
  }
}


// Flatten an array into a word.
fn flatten<N:u32, M:u32, TOTAL:u32={N*M}>(value: uN[N][M]) -> uN[TOTAL] {
  value as uN[TOTAL]
}

// Expands a mask of NUM_PARTITIONS bits to a mask of DATA_WIDTH bits, repeating
// each bit in the smaller mask. The RAM model has a notion of "partitions", a
// group of (potentially many) bits that are all activated by a single bit in
// the mask. When masking data bits, it is useful to expand the mask from 1 bit
// per partition to one bit bit per data bit.
fn expand_mask<DATA_WIDTH:u32, NUM_PARTITIONS:u32,
 EXPANSION_FACTOR:u32={std::ceil_div(DATA_WIDTH, NUM_PARTITIONS)}>(
  partition_mask:uN[NUM_PARTITIONS]) -> uN[DATA_WIDTH] {
  for (idx, data_mask): (u32, uN[DATA_WIDTH]) in range(u32:0, NUM_PARTITIONS) {
    let data_mask_segment =
      flatten(u1[EXPANSION_FACTOR]: [partition_mask[idx +: u1], ...]);
    ((data_mask_segment as uN[DATA_WIDTH]) << (idx * EXPANSION_FACTOR)) |
      data_mask
  } (uN[DATA_WIDTH]:0)
}

// Writes value `write_value` with write mask `mask` over previous value
// `mem_word`. The first element in the return tuple is the updated value and
// the second is the updated initialization.
fn write_word<DATA_WIDTH:u32, NUM_PARTITIONS:u32>(
  mem_word: uN[DATA_WIDTH],
  mem_initialized: bool[NUM_PARTITIONS],
  write_value: uN[DATA_WIDTH],
  mask: uN[NUM_PARTITIONS],
) -> (uN[DATA_WIDTH], bool[NUM_PARTITIONS]) {
  // TODO: compute mask when NUM_PARTITIONS != DATA_WIDTH
  let expanded_mask = expand_mask<DATA_WIDTH>(mask);
  let new_word = (mem_word & !expanded_mask) | (write_value & expanded_mask);
  let new_initialization =
    for (idx, partial_initialization): (u32, bool[NUM_PARTITIONS]) in
    range(u32:0, NUM_PARTITIONS) {
      if mask[idx+:bool] {
        update(partial_initialization, idx, true)
      } else { partial_initialization }
  } (mem_initialized);
  (new_word, new_initialization)
}

proc RamModel<DATA_WIDTH:u32, SIZE:u32, WORD_PARTITION_SIZE:u32={u32:0},
  SIMULTANEOUS_READ_WRITE_BEHAVIOR:SimultaneousReadWriteBehavior=
   {SimultaneousReadWriteBehavior::READ_BEFORE_WRITE},
  INITIALIZED:bool={false},
  ASSERT_VALID_READ:bool={true}, ADDR_WIDTH:u32 = {std::clog2(SIZE)},
  NUM_PARTITIONS:u32={u32:1}> {

  read_req: chan<ReadReq<ADDR_WIDTH, NUM_PARTITIONS>> in;
  read_resp: chan<ReadResp<DATA_WIDTH>> out;
  write_req: chan<WriteReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> in;
  write_resp: chan<WriteResp> out;

  init {
      (
        // mem contents initialized to whatever INITIAL_VALUE contains (zero by
        // default).
        // TODO(google/xls#818): use a parameter for the initial value.
        uN[DATA_WIDTH][SIZE]:[uN[DATA_WIDTH]:0,...],
        // mem_initialized initialized to whatever INITIALIZED is (false by
        // default, indicating no data has been written yet).
        bool[NUM_PARTITIONS][SIZE]:
         [bool[NUM_PARTITIONS]:[INITIALIZED, ...], ...],
      )
  }

  config(
    read_req: chan<ReadReq<ADDR_WIDTH, NUM_PARTITIONS>> in,
    read_resp: chan<ReadResp<DATA_WIDTH>> out,
    write_req: chan<WriteReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>> in,
    write_resp: chan<WriteResp> out,
  ) {
    (read_req, read_resp, write_req, write_resp)
  }

  next(state:(bits[DATA_WIDTH][SIZE], bool[NUM_PARTITIONS][SIZE])) {
    // state consists of an array storing the memory state, as well as an array
    // indicating if the each subword partition has been initialized.
    let (mem, mem_initialized) = state;

    // Perform nonblocking receives on each request channel.
    let zero_read_req = ReadReq<ADDR_WIDTH, NUM_PARTITIONS> {
      addr:bits[ADDR_WIDTH]:0,
      mask:bits[NUM_PARTITIONS]:0,
    };
    let (tok, read_req, read_req_valid) =
      recv_non_blocking(join(), read_req, zero_read_req);
    let zero_write_req = WriteReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS> {
      addr:bits[ADDR_WIDTH]:0,
      data:bits[DATA_WIDTH]:0,
      mask:bits[NUM_PARTITIONS]:0,
    };
    let (tok, write_req, write_req_valid) =
      recv_non_blocking(tok, write_req, zero_write_req);

    // Assert memory being read is initialized by checking that all partitions
    // have been initialized.
    //if read_req_valid && ASSERT_VALID_READ {
    //  let mem_initialized_as_bits =
    //    std::convert_to_bits_msb0(array_rev(mem_initialized[read_req.addr]));
    //  assert_eq(read_req.mask & !mem_initialized_as_bits, uN[NUM_PARTITIONS]:0)
    //} else { () };

    let (value_to_write, written_mem_initialized) = write_word(
      mem[write_req.addr], mem_initialized[write_req.addr],
      write_req.data, write_req.mask);

    let unmasked_read_value =
     if write_req_valid && read_req.addr == write_req.addr {
      // If we are simultaneously reading and writing the same address, check
      // SIMULTANEOUS_READ_WRITE_BEHAVIOR for the desired behavior.
      match SIMULTANEOUS_READ_WRITE_BEHAVIOR {
        SimultaneousReadWriteBehavior::READ_BEFORE_WRITE => mem[read_req.addr],
        SimultaneousReadWriteBehavior::WRITE_BEFORE_READ => value_to_write,
        SimultaneousReadWriteBehavior::ASSERT_NO_CONFLICT => {
          // Assertion failure, we have a conflicting read and write.
          // assert_eq(true, false);
          mem[read_req.addr]  // Need to return something.
        },
        _ => mem[read_req.addr]
      }
    } else { mem[read_req.addr] };
    let read_resp_value = ReadResp<DATA_WIDTH> {
      data: unmasked_read_value & expand_mask<DATA_WIDTH>(read_req.mask),
    };
    let tok = send_if(tok, read_resp, read_req_valid, read_resp_value);

    // If we're doing a write, update the memory and mem_initialized. We
    // previously computed the updated values as they were potentially needed
    // for reads if writes were visible before reads.
    let mem = if write_req_valid {
      update(mem, write_req.addr, value_to_write)
    } else { mem };
    let mem_initialized = if write_req_valid {
      update(mem_initialized, write_req.addr, written_mem_initialized)
    } else { mem_initialized };
    let tok = send_if(tok, write_resp, write_req_valid, WriteResp{});

    (mem, mem_initialized)
  }
}

/////////////////////////////////////////////////////////////////////////////

pub const SNAPPY_MAX_HISTORY_BYTES = u32:32768;
pub const SNAPPY_MIN_COPY_LEN = u32:4;

pub const BUS_BYTES = u32:8;
pub const BUS_BITS  = BUS_BYTES * u32:8;
pub const CAPACITY  = BUS_BITS;
pub const BYTE = u32:8;

pub type BusBytesBundle = bits[BUS_BITS];

pub enum SnappyOpcode : u2 {
  LITERAL = 0,
  COPY_1BYTE_OFFSET = 1,
  COPY_2BYTE_OFFSET = 2,
  COPY_4BYTE_OFFSET = 3,
}

pub struct SnappyDecompInfo {
  compressed_file_bytes: u32
}

pub struct DataBundle {
  data: bits[BUS_BITS],
  valid_bytes: u32,
  is_last: bool
}

pub struct CopyInfo {
  offset: u32,
  copy_len: u32,
}

pub struct LitInfo {
  litlen: u32
}

pub struct SnpyCmd {
  is_copy: bool,
  copy_info: CopyInfo,
  lit_info: LitInfo
}

pub struct SnpyCmdOrData {
  is_cmd: bool,
  cmd: SnpyCmd,
  data: DataBundle,
  is_last: bool
}

/////////////////////////////////////////////////////////////////////////////

pub enum BufferStatus : u2 {
  OK = 0,
  FAILED = 1,
}

pub struct RotBuffer {
  content: bits[BUS_BITS],
  received_so_far_bytes: u32,
  sent_so_far_bytes: u32,
  received_last_chunk: bool
}

pub struct RotBufferResult {
  rotbuffer: RotBuffer,
  status: BufferStatus
}

pub fn rotbuf_valid_bytes(
  rotbuffer: RotBuffer
) -> u32 {
  rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes
}

pub fn rotbuf_is_last_chunk(
  rotbuffer: RotBuffer,
  bus_bits: u32
) -> bool {
  let valid_bytes = rotbuf_valid_bytes(rotbuffer);
  let bus_bytes = bus_bits >> 3;
  rotbuffer.received_last_chunk && (valid_bytes <= bus_bytes)
}

pub fn rotbuf_can_fit(
  rotbuffer: RotBuffer, input_size_bytes: u32
) -> bool {
  let free_bytes = (CAPACITY >> 3) - rotbuf_valid_bytes(rotbuffer);
  free_bytes >= input_size_bytes
}

pub fn rotbuf_append_unsafe(
  rotbuffer: RotBuffer, databundle: DataBundle
) -> RotBuffer {
  let rotbuffer_bits = (rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes) << 3;
  RotBuffer {
    content: (databundle.data as bits[CAPACITY] << rotbuffer_bits) | rotbuffer.content,
    received_so_far_bytes: rotbuffer.received_so_far_bytes + databundle.valid_bytes,
    received_last_chunk: databundle.is_last,
    ..rotbuffer
  }
}

pub fn rotbuf_append(
  rotbuffer: RotBuffer, databundle: DataBundle
) -> RotBufferResult {
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

pub fn rotbuf_has_at_least(
  rotbuffer: RotBuffer, output_size_bytes: u32
) -> bool {
  let valid_bytes = rotbuffer.received_so_far_bytes - rotbuffer.sent_so_far_bytes;
  valid_bytes >= output_size_bytes
}

pub fn rotbuf_peek_unsafe(
  rotbuffer: RotBuffer, bytes_to_peek: u32
) -> bits[CAPACITY] {
  let bits_to_peek  = bytes_to_peek << 3;
  let mask = (bits[CAPACITY]:1 << bits_to_peek as bits[CAPACITY]) - bits[CAPACITY]:1;
  rotbuffer.content & mask
}

pub fn rotbuf_peek(
  rotbuffer: RotBuffer, bytes_to_peek: u32
) -> (bool, bits[CAPACITY]) {
  if rotbuf_has_at_least(rotbuffer, bytes_to_peek) == false{
    (false, zero!<bits[CAPACITY]>())
  } else {
    let bits_to_peek  = bytes_to_peek << 3;
    let mask = (bits[CAPACITY]:1 << bits_to_peek as bits[CAPACITY]) - bits[CAPACITY]:1;
    (true, rotbuffer.content & mask)
  }
}

pub fn rotbuf_pop_unsafe(
  rotbuffer: RotBuffer, bytes_to_pop: u32
) -> (RotBuffer, bits[CAPACITY]) {
  let bits_to_pop = bytes_to_pop << 3;
  // let mask = (bits[CAPACITY]:1 << bits_to_pop as bits[CAPACITY]) - bits[CAPACITY]:1;
  (
    RotBuffer {
      content: rotbuffer.content >> bits_to_pop,
      sent_so_far_bytes: rotbuffer.sent_so_far_bytes + bytes_to_pop,
      ..rotbuffer
    },
    rotbuf_peek_unsafe(rotbuffer, bytes_to_pop)
  )
}

pub fn rotbuf_pop(
  rotbuffer: RotBuffer, bytes_to_pop: u32
) -> (RotBufferResult, bits[CAPACITY]) {
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

////////////////////////////////////////////////////////////////////////

type uBusBits = uN[BUS_BITS];

const SRAM_WORD_BITS = BYTE;
const SRAM_WORD_CNT = SNAPPY_MAX_HISTORY_BYTES / BUS_BYTES;
const SRAM_WORD_MASK = BYTE;
const SRAM_RW_BEHAVIOR = SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
const SRAM_NUM_PARTITIONS = u32:1;
const SRAM_INIT = true;
const SRAM_ADDR_BITS = u32:12;

pub enum CommandExecuterFSM : u2 {
  SET_COMMAND = 0,
  SHIP_LITERALS = 1,
  PERFORM_COPY = 2
}

struct SnappyCommandExecuterState {
  fsm: CommandExecuterFSM,
  cur_cmd: SnpyCmd,
  cmdordata: SnpyCmdOrData,
  historybuffer_ptr: u32, // assume filesizes <= 4GB
  cur_litlen_shipped: u32,
  cur_copy_databundle: DataBundle
}

proc SnappyCommandExecuter {
  sram_rd0_req_s: chan<ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd0_resp_r: chan<ReadResp<SRAM_WORD_BITS>> in;

  sram_wr0_req_s: chan<WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr0_resp_r: chan<WriteResp> in;

  init {
    (zero!<SnappyCommandExecuterState>())
  }

  config() {
    let (sram_rd0_req_s, sram_rd0_req_r) = chan<ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd0_req");
    let (sram_rd0_resp_s, sram_rd0_resp_r) = chan<ReadResp<SRAM_WORD_BITS>>("sram_rd0_resp");
    let (sram_wr0_req_s, sram_wr0_req_r) = chan<WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr0_req");
    let (sram_wr0_resp_s, sram_wr0_resp_r) = chan<WriteResp>("sram_wr0_resp");

    spawn RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd0_req_r, sram_rd0_resp_s,
        sram_wr0_req_r, sram_wr0_resp_s);
    (sram_rd0_req_s, sram_rd0_resp_r,
     sram_wr0_req_s, sram_wr0_resp_r)
  }

  next(state: SnappyCommandExecuterState) {
    state
  }
}
