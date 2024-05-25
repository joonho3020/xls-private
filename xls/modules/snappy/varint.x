
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;

const BUS_BITS = common::BUS_BITS;

struct VarInt {
  more_bytes: u1,
  data: u8
}

fn decode_to_varint(byte: u8) -> VarInt {
  let mask = (u8:0xff);
  VarInt {
    more_bytes: (byte >> u8:7),
    data: (byte & mask)
  }
}
