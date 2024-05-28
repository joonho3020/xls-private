
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:50;
const SNAPPY_MIN_COPY_LEN = common::SNAPPY_MIN_COPY_LEN;

type RotBuffer = buff::RotBuffer<BUFFER_BITS>;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;

type CopyInfo = common::CopyInfo;
type LitInfo = common::LitInfo;
type SnpyCmd = common::SnpyCmd;
type SnpyCmdOrData = common::SnpyCmdOrData<BUS_BITS>;

pub enum CopySplitterFSM: u3 {
  SHIP_LITERALS_OR_COMMANDS = 0,
  SPLIT_COPY_COMMANDS = 1
}

struct SnappyCopySplitterState {
  fsm: CopySplitterFSM,
  cmdordata_valid: bool,
  cmdordata: SnpyCmdOrData,
  sent_copy_len: u32
}

pub fn ship_literals_or_commands(state: SnappyCopySplitterState) ->
    (bool, SnpyCmdOrData, SnappyCopySplitterState) {
  let do_send = state.cmdordata_valid;
  let newstate = SnappyCopySplitterState {
    cmdordata_valid: false,
    ..state
  };
  trace_fmt!("[SnpyCopySplitter] ship_literals_or_commands do_send {}, nextstate {:x}",
    do_send, newstate);
  (do_send, state.cmdordata, newstate)
}

pub fn split_copy_commands(state: SnappyCopySplitterState) ->
    (bool, SnpyCmdOrData, SnappyCopySplitterState) {
  assert_eq(state.cmdordata_valid, true);
  assert_eq(state.cmdordata.is_cmd, true);
  assert_eq(state.cmdordata.cmd.is_copy, true);

  let copy_info = state.cmdordata.cmd.copy_info;
  let last_copy_to_ship = (copy_info.copy_len <= state.sent_copy_len + SNAPPY_MIN_COPY_LEN);
  let remaining_copy_bytes = copy_info.copy_len - state.sent_copy_len;
  let copy_len_to_ship = std::umin(SNAPPY_MIN_COPY_LEN, remaining_copy_bytes);
  let cmdordata_to_ship = SnpyCmdOrData {
    is_cmd: true,
    cmd: SnpyCmd {
      is_copy: true,
      copy_info: CopyInfo {
        offset: copy_info.offset + state.sent_copy_len,
        copy_len: copy_len_to_ship
      },
      lit_info: zero!<LitInfo>()
    },
    data: zero!<DataBundle>()
  };

  let (nxt_fsm, nxt_sent_copy_len, nxt_cmdordata_valid) = if last_copy_to_ship {
    (CopySplitterFSM::SHIP_LITERALS_OR_COMMANDS, u32:0, false)
  } else {
    (state.fsm, state.sent_copy_len + copy_len_to_ship, true)
  };
  let next_state = SnappyCopySplitterState {
    fsm: nxt_fsm,
    sent_copy_len: nxt_sent_copy_len,
    cmdordata_valid: nxt_cmdordata_valid,
    ..state
  };
  trace_fmt!("[SnpyCopySplitter] split_copy_commands cmdordata {:x} nextstate {:x}",
    cmdordata_to_ship, next_state);
  (true, cmdordata_to_ship, next_state)
}

proc SnappyCopySplitter {
  cmdordata_in: chan<SnpyCmdOrData> in;
  cmdordata_out: chan<SnpyCmdOrData> out;

  init {
    (zero!<SnappyCopySplitterState>())
  }

  config(cmdordata_in: chan<SnpyCmdOrData> in,
         cmdordata_out: chan<SnpyCmdOrData> out) {
    (cmdordata_in, cmdordata_out)
  }

  next(tok: token, state: SnappyCopySplitterState) {
    let recv_ready = (state.fsm != CopySplitterFSM::SPLIT_COPY_COMMANDS);
    let (tok, cmdordata, recv_valid) = recv_if_non_blocking(tok, cmdordata_in, recv_ready, zero!<SnpyCmdOrData>());
    trace_fmt!("[SnpyCopySPlitter] recv 0x{:x}", cmdordata);
    let state = if (recv_valid && recv_ready) {
      let fsm = if (cmdordata.is_cmd && cmdordata.cmd.is_copy) {
        CopySplitterFSM::SPLIT_COPY_COMMANDS
      } else {
        CopySplitterFSM::SHIP_LITERALS_OR_COMMANDS
      };
      SnappyCopySplitterState {
        fsm: fsm,
        cmdordata: cmdordata,
        cmdordata_valid: true,
        ..state
      }
    } else {
      state
    };

    let (do_send, cmdordata, state) = match state.fsm {
      CopySplitterFSM::SHIP_LITERALS_OR_COMMANDS =>
        ship_literals_or_commands(state),
      CopySplitterFSM::SPLIT_COPY_COMMANDS =>
        split_copy_commands(state),
      _ => (false, zero!<SnpyCmdOrData>(), state)
    };

    if (do_send) {
      send(tok, cmdordata_out, cmdordata);
    } else {
    };

    state
  }
}
