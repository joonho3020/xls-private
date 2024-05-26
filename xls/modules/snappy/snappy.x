
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;

const BUS_BITS = common::BUS_BITS;
const BYTE     = common::BYTE;

type Buffer = buff::Buffer;
type BusBytes = common::BusBytes;

pub enum SnappyFSMStates : u2 {
  VARINT_DECODE = 0,
  DECOMPRESS = 1
}

struct SnappyState {
  buffer: Buffer<BUS_BITS>,
  varint_idx: u32,
  decomp_len: u32,
  fsm: SnappyFSMStates
}

fn snappy_varint_decode(state: SnappyState) -> (bool, BusBytes, SnappyState) {
  let (br, data) = buff::buffer_pop(state.buffer, BYTE);

  if br.status == buff::BufferStatus::FAILED {
    (false, zero!<BusBytes>(), state)
  } else {
    let vi = varint::decode_to_varint(data as u8);
    let varint_to_add = vi.data << ((state.varint_idx * u32:7) as u8);
    let nxt_fsm_state = if vi.more_bytes == u1:0 {
      SnappyFSMStates::DECOMPRESS
    } else {
      state.fsm
    };
    let new_state = SnappyState {
      buffer: br.buffer,
      varint_idx: state.varint_idx + u32:1,
      decomp_len: state.decomp_len + varint_to_add as u32,
      fsm: nxt_fsm_state
    };
    (false, zero!<BusBytes>(), new_state)
  }
}

fn snappy_decompress(state: SnappyState) -> (bool, BusBytes, SnappyState) {
  let (buffer_result, bits_from_buffer) = buff::buffer_pop(state.buffer, BUS_BITS);
  (
    false,
    bits_from_buffer,
    SnappyState {
      buffer: buffer_result.buffer,
      varint_idx: state.varint_idx,
      decomp_len: state.decomp_len,
      fsm: state.fsm
    }
  )
}

pub proc Snappy {
  comp_data_r: chan<BusBytes> in;
  decomp_data_s: chan<BusBytes> out;

  init {
    (zero!<SnappyState>())
  }

  config (
    comp_data_r: chan<BusBytes> in,
    decomp_data_s: chan<BusBytes> out
  ) {
    (comp_data_r, decomp_data_s)
  }

  next (tok: token, state: SnappyState) {
    let can_fit = buff::buffer_can_fit(state.buffer, BusBytes:0);
    let (tok, data, recv_valid) = recv_if_non_blocking(tok, comp_data_r, can_fit, BusBytes:0);
    let state = if (can_fit && recv_valid) {
      let buffer_result = buff::buffer_append(state.buffer, data);
      SnappyState {
        buffer: buffer_result.buffer,
        ..state
      }
    } else {
      state
    };

    let (send, data_to_send, state) = match state.fsm {
      SnappyFSMStates::VARINT_DECODE =>
        snappy_varint_decode(state),
      SnappyFSMStates::DECOMPRESS =>
        snappy_decompress(state),
      _ => (false, zero!<BusBytes>(), state)
    };

    state
  }
}
