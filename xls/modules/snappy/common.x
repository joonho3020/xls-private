

pub const SNAPPY_MAX_HISTORY_BYTES = u32:32768;
pub const SNAPPY_MIN_COPY_LEN = u32:4;

pub const BUS_BYTES = u32:8;
pub const BUS_BITS  = BUS_BYTES * u32:8;
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

pub struct DataBundle<CAPACITY: u32> {
  data: bits[CAPACITY],
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

pub struct SnpyCmdOrData<CAPACITY: u32> {
  is_cmd: bool,
  cmd: SnpyCmd,
  data: DataBundle<CAPACITY>,
  is_last: bool
}
