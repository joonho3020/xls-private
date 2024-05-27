
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:4;

type Buffer = buff::Buffer;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;
type SnpyCmdOrData = common::SnpyCmdOrData<BUS_BITS>;


pub enum CopyExpanderFSM : u3 {
  DECODE_TAG = 0,
  DECODE_LITERALS_EXTRA_BYTES = 1,
  DECODE_COPYCMD_EXTRA_BYTES = 2,
  SHIP_LITERALS = 3
}

struct SnappyCommandExpanderState {
  fsm: CopyExpanderFSM,
  buffer: Buffer<BUFFER_BITS>
}


//pub fn decode_tag(state: SnappyCommandExpanderState) -> SnappyCommandExpanderState {
//  let (br, snappy_tag) = buff::buffer_pop(state.databundle.buffer, BYTE);
//  if br.status == buff::BufferStatus::OK {
//    let snpy_op = snappy_tag[0:2];
//    let upper_tag = snappy_tag[2:8] as u32;
//
//    // literal command
//    if (snpy_op == u2:0) {
//      if (upper_tag < u32:60) {
//        // short literals : start shipping literals
//        SnappyCommandExpanderState {
//          fsm: CopyExpanderFSM::SHIP_LITERALS,
//          tag_extra_bytes: u32:0,
//          databundle: DataBundle {
//            buffer: br.buffer,
//            is_last: state.databundle.is_last
//          }
//        }
//      } else {
//        // long literals : need to decode extra tags
//        let tag_extra_bytes = upper_tag - u32:60 + u32:1;
//        SnappyCommandExpanderState {
//          fsm: CopyExpanderFSM::DECODE_LITERALS_EXTRA_BYTES,
//          tag_extra_bytes: tag_extra_bytes,
//          databundle: DataBundle {
//            buffer: br.buffer,
//            is_last: state.databundle.is_last
//          }
//        }
//      }
//    } else if (snpy_op == u2:1) { // copy with 1-byte offset
//      let = copy_len
//    } else if (snpy_op == u2:2) { // copy with 2-byte offset
//    } else { // copy with 4-byte offset
//    }
//  } else {
//    state
//  }
//}

proc SnappyCommandExpander {
  incoming_data_bundle: chan<DataBundle> in;
  snappy_cmd_or_data_out: chan<SnpyCmdOrData> out;

  init {
    (zero!<SnappyCommandExpanderState>())
  }

  config(incoming_data_bundle: chan<DataBundle> in,
         snappy_cmd_or_data_out: chan<SnpyCmdOrData> out) {
    (incoming_data_bundle, snappy_cmd_or_data_out)
  }

  next(tok: token, state: SnappyCommandExpanderState) {
    let recv_ready = buff::buffer_can_fit(state.buffer, BusBytesBundle:0);
    let (tok, databundle, recv_valid) = recv_if_non_blocking(tok, incoming_data_bundle, recv_ready, zero!<DataBundle>());
    let state = if (recv_valid && recv_ready) {
      trace_fmt!("[SnpyCommandExpander] recv data {:x} bytes {} last {}", databundle.data, databundle.valid_bytes, databundle.is_last);
      // let valid_bits = databundle.valid_bytes << 3;
      // let buff_data = databundle.data as bits[valid_bits];
      let buffer_result = buff::buffer_append(state.buffer, databundle.data);
      trace_fmt!("[SnpyCommandExpander] buffer {:x} {}", buffer_result.buffer.content, buffer_result.buffer.length);
      SnappyCommandExpanderState {
        buffer: buffer_result.buffer,
        ..state
      }
    } else {
      state
    };
    state

    //let (do_send, cmdordata_to_send, state) = match state.fsm {
    //  CopyExpanderFSM::DECODE_TAG =>
    //    decode_tag(state),
    //  CopyExpanderFSM::SHIP_LITERALS =>
    //    ship_literals(state),
    //  _ => (false, zero!<SnpyCmdOrData>(), state)
    //};
    //???
  }
}
