
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:50;

type RotBuffer = buff::RotBuffer<BUFFER_BITS>;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;

type CopyInfo = common::CopyInfo;
type LitInfo = common::LitInfo;
type SnpyCmd = common::SnpyCmd;
type SnpyCmdOrData = common::SnpyCmdOrData<BUS_BITS>;


pub enum CopyExpanderFSM : u3 {
  DECODE_TAG = 0,
  SHIP_LITERALS = 1
}

struct SnappyCommandExpanderState {
  fsm: CopyExpanderFSM,
  rotbuffer: RotBuffer,
  cur_litlen: u32,
  sent_litlen: u32
}

pub fn set_copy_cmd(offset: u32, copy_len: u32) -> SnpyCmdOrData {
  let ret = SnpyCmdOrData {
    is_cmd: true,
    cmd: SnpyCmd {
      is_copy: true,
      copy_info: CopyInfo {
        offset: offset,
        copy_len: copy_len
      },
      lit_info: zero!<LitInfo>()
    },
    data: zero!<DataBundle>()
  };
  trace_fmt!("[SnpyCommandExpander] set_copy_cmd: {}", ret);
  ret
}

pub fn set_lit_cmd(litlen: u32) -> SnpyCmdOrData {
  let ret = SnpyCmdOrData {
    is_cmd: true,
    cmd : SnpyCmd {
      is_copy: false,
      copy_info: zero!<CopyInfo>(),
      lit_info: LitInfo { litlen: litlen }
    },
    data: zero!<DataBundle>()
  };
  trace_fmt!("[SnpyCommandExpander] set_lit_cmd: {}", ret);
  ret
}

pub fn decode_tag(state: SnappyCommandExpanderState) ->
    (bool, SnpyCmdOrData, SnappyCommandExpanderState) {
  let rotbuf_valid_bytes = buff::rotbuf_valid_bytes(state.rotbuffer);
  if rotbuf_valid_bytes < u32:1 {
    (false, zero!<SnpyCmdOrData>(), state)
  } else {
    let (_, tag) = buff::rotbuf_peek(state.rotbuffer, u32:1);
    let opcode = tag[0:2] as common::SnappyOpcode;
    let upper_tag = tag[2:8] as u32;

    // literal
    if (opcode == common::SnappyOpcode::LITERAL) {
      if (upper_tag < u32:60) { // Short literal: starting shipping literals
        let (rbr, _) = buff::rotbuf_pop(state.rotbuffer, u32:1);
        let litlen = upper_tag + u32:1;

        let newstate = SnappyCommandExpanderState {
          fsm: CopyExpanderFSM::SHIP_LITERALS,
          rotbuffer: rbr.rotbuffer,
          cur_litlen: litlen,
          sent_litlen: u32:0
        };
        (true, set_lit_cmd(litlen), newstate)
      } else { // Long literal
        let extra_bytes = upper_tag - u32:60 + u32:1;

        if (rotbuf_valid_bytes >= u32:1 + extra_bytes) {
          // enough bytes to compute the litlen, start shipping literals
          let (rbr, _)      = buff::rotbuf_pop(state.rotbuffer, u32:1);
          let (rbr, litlen) = buff::rotbuf_pop(rbr.rotbuffer, extra_bytes);
          let litlen = (litlen as u32) + u32:1;

          let newstate = SnappyCommandExpanderState {
            fsm: CopyExpanderFSM::SHIP_LITERALS,
            rotbuffer: rbr.rotbuffer,
            cur_litlen: litlen,
            sent_litlen: u32:0
          };
          (true, set_lit_cmd(litlen), newstate)
        } else { // not enough bytes yet
          (false, zero!<SnpyCmdOrData>(), state)
        }
      }
    } else if (opcode == common::SnappyOpcode::COPY_1BYTE_OFFSET) {
      if (rotbuf_valid_bytes >= u32:2) {
        let (rbr,  _) = buff::rotbuf_pop(state.rotbuffer, u32:1);
        let (rbr, eb) = buff::rotbuf_pop(rbr.rotbuffer, u32:1);
        let copy_len = upper_tag[0:3] as u32 + u32:4;
        let offset = (upper_tag[3:6] as u32 << 8) + (eb as u32);

        let newstate = SnappyCommandExpanderState {
          fsm: CopyExpanderFSM::DECODE_TAG,
          rotbuffer: rbr.rotbuffer,
          ..state
        };
        (true, set_copy_cmd(offset, copy_len), newstate)
      } else {
        (false, zero!<SnpyCmdOrData>(), state)
      }
    } else if (opcode == common::SnappyOpcode::COPY_2BYTE_OFFSET) {
      if (rotbuf_valid_bytes >= u32:3) {
        let (rbr,  _) = buff::rotbuf_pop(state.rotbuffer, u32:1);
        let (rbr, eb) = buff::rotbuf_pop(rbr.rotbuffer, u32:2);
        let copy_len = upper_tag[0:3] as u32 + u32:1;
        let offset = eb as u32;

        let newstate = SnappyCommandExpanderState {
          fsm: CopyExpanderFSM::DECODE_TAG,
          rotbuffer: rbr.rotbuffer,
          ..state
        };
        (true, set_copy_cmd(offset, copy_len), newstate)
      } else {
        (false, zero!<SnpyCmdOrData>(), state)
      }
    } else if (opcode == common::SnappyOpcode::COPY_4BYTE_OFFSET) {
      if (rotbuf_valid_bytes >= u32:5) {
        let (rbr,  _) = buff::rotbuf_pop(state.rotbuffer, u32:1);
        let (rbr, eb) = buff::rotbuf_pop(rbr.rotbuffer, u32:4);
        let copy_len = upper_tag[0:3] as u32 + u32:1;
        let offset = eb as u32;

        let newstate = SnappyCommandExpanderState {
          fsm: CopyExpanderFSM::DECODE_TAG,
          rotbuffer: rbr.rotbuffer,
          ..state
        };
        (true, set_copy_cmd(offset, copy_len), newstate)
      } else {
        (false, zero!<SnpyCmdOrData>(), state)
      }
    } else {
      (false, zero!<SnpyCmdOrData>(), state)
    }
  }
}

pub fn ship_literals(state: SnappyCommandExpanderState) ->
    (bool, SnpyCmdOrData, SnappyCommandExpanderState) {
  let remaining_bytes_to_send = state.cur_litlen - state.sent_litlen;
  let bytes_to_send_now = std::umin(remaining_bytes_to_send, BUS_BYTES);
  let is_last_chunk = buff::rotbuf_is_last_chunk(state.rotbuffer, BUS_BITS);
  let (rotbuf_pop_result, data) = buff::rotbuf_pop(state.rotbuffer, bytes_to_send_now);

  if (rotbuf_pop_result.status == buff::BufferStatus::FAILED) {
    (false, zero!<SnpyCmdOrData>(), state)
  } else {
    let sent_litlen = if is_last_chunk { u32:0 } else { state.sent_litlen + bytes_to_send_now };
    let cur_litlen = if is_last_chunk { u32:0 } else { state.cur_litlen };
    let fsm = if is_last_chunk || (remaining_bytes_to_send <= BUS_BYTES) {
      CopyExpanderFSM::DECODE_TAG
    } else {
      CopyExpanderFSM::SHIP_LITERALS
    };
    let newstate = SnappyCommandExpanderState {
      cur_litlen: cur_litlen,
      sent_litlen: sent_litlen,
      rotbuffer: rotbuf_pop_result.rotbuffer,
      fsm: fsm
    };
    let cmdordata = SnpyCmdOrData {
      is_cmd: false,
      cmd: zero!<SnpyCmd>(),
      data: DataBundle {
        data: data as bits[BUS_BITS],
        valid_bytes: bytes_to_send_now,
        is_last: is_last_chunk
      }
    };
    trace_fmt!("[SnpyCommandExpander] ship_literals cmd {:x} state {:x}",
      cmdordata, newstate);
    (true, cmdordata, newstate)
  }
}

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
    let recv_ready = buff::rotbuf_can_fit(state.rotbuffer, BUS_BYTES);
    let (tok, databundle, recv_valid) = recv_if_non_blocking(tok, incoming_data_bundle, recv_ready, zero!<DataBundle>());
    let state = if (recv_valid && recv_ready) {
      let buffer_result = buff::rotbuf_append(state.rotbuffer, databundle);
      trace_fmt!("[SnpyCommandExpander] recv data {:x} bytes {} last {}",
        databundle.data, databundle.valid_bytes, databundle.is_last);
      trace_fmt!("[SnpyCommandExpander] rotbuffer {:x} {}",
        buffer_result.rotbuffer.content,
        buff::rotbuf_valid_bytes(buffer_result.rotbuffer));
      SnappyCommandExpanderState {
        rotbuffer: buffer_result.rotbuffer,
        ..state
      }
    } else {
      state
    };

    let (do_send, cmdordata_to_send, state) = match state.fsm {
      CopyExpanderFSM::DECODE_TAG =>
        decode_tag(state),
      CopyExpanderFSM::SHIP_LITERALS =>
        ship_literals(state),
      _ => (false, zero!<SnpyCmdOrData>(), state)
    };

    if (do_send) {
      send(tok, snappy_cmd_or_data_out, cmdordata_to_send);
    } else {
    };

    state
  }
}
