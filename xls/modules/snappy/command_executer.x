
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;
import xls.examples.ram;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:50;

const SnappyMaxHistorySizeBytes = common::SnappyMaxHistorySizeBytes;
const SRAM_WORD_BITS = BYTE;
const SRAM_WORD_CNT = SnappyMaxHistorySizeBytes / BUS_BYTES;
const SRAM_WORD_MASK = BYTE;
const SRAM_RW_BEHAVIOR = ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
const SRAM_NUM_PARTITIONS = ram::num_partitions(SRAM_WORD_MASK, SRAM_WORD_BITS);
const SRAM_INIT = true;
const SRAM_ADDR_BITS = std::clog2(SRAM_WORD_CNT);
type ReadReq = ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>;
type ReadResp = ram::ReqdResp<SRAM_WORD_BITS>;
type WriteReq = ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>;
type WriteResp = ram::WriteResp;

type RotBuffer = buff::RotBuffer<BUFFER_BITS>;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;

type CopyInfo = common::CopyInfo;
type LitInfo = common::LitInfo;
type SnpyCmd = common::SnpyCmd;
type SnpyCmdOrData = common::SnpyCmdOrData<BUS_BITS>;


pub enum CommandExecuterFSM : u2 {
  SET_COMMAND = 0,
  SHIP_LITERALS = 1,
  PERFORM_COPY = 2
}

struct SnappyCommandExecuterState {
  fsm: CommandExecuterFSM,
  recv_cmdordata_valid: bool,
  recv_cmdordata_ready: bool,
  cur_cmd: SnpyCmd,
  cmdordata: SnpyCmdOrData,
  historybuffer_ptr: u32, // assume filesizes <= 4GB
  cur_litlen_shipped: u32,
  cur_copylen_shipped: u32
}

pub fn set_command(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  if state.recv_cmdordata_valid == false {
    (false, false, state)
  } else {
    assert_eq(state.cmdordata.is_cmd, true);
    let is_copy = state.cmdordata.cmd.is_copy;
    let (next_fsm, recv_ready) = if (state.cmdordata.cmd.is_copy) {
      (CommandExecuterFSM::PERFORM_COPY, false)
    } else {
      (CommandExecuterFSM::SHIP_LITERALS, true)
    };
    let next_state = SnappyCommandExecuterState {
      fsm: next_fsm,
      recv_cmdordata_ready: recv_ready,
      recv_cmdordata_valid: false,
      cur_cmd: state.cmdordata.cmd,
      ..state
    };
    (false, false, next_state)
  }
}

pub fn ship_literals(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  if state.recv_cmdordata_valid == false {
    (false, false, state)
  } else {
    (true, false, state)
  }
}

pub fn perform_copy(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  (false, true, state)
}

proc SnappyCommandExecuter {
  cmdordata_in: chan<SnpyCmdOrData> in;
  decompressed_output: chan<DataBundle> out;

  sram_rd_req_s: chan<ReadReq>[BUS_BYTES] out;
  sram_rd_resp_r: chan<ReadReq>[BUS_BYTES] in;
  sram_wr_req_s: chan<WriteReq>[BUS_BYTES] out;
  sram_wr_resp_r: chan<WriteReq>[BUS_BYTES] in;

  init {
    (zero!<SnappyCommandExecuterState>())
  }

  config(cmdordata_in: chan<SnpyCmdOrData> in,
         decompressed_output: chan<DataBundle> out) {
    let (sram_rd_req_s, sram_rd_req_r) = chan<ReadReq>[BUS_BYTES]("sram_rd_req");
    let (sram_rd_resp_s, sram_rd_resp_r) = chan<ReadResp>[BUS_BYTES]("sram_rd_resp");
    let (sram_wr_req_s, sram_wr_req_r) = chan<WriteReq>[BUS_BYTES]("sram_wr_req");
    let (sram_wr_resp_s, sram_wr_resp_r) = chan<WriteResp>[BUS_BYTES]("sram_wr_resp");

    for (i, _) : (u32, ()) in range(u32:0, BUS_BYTES) {
      spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
        SRAM_RW_BEHAVIOR, SRAM_INIT> (
          sram_rd_req_r[i], sram_rd_resp_s[i],
          sram_wr_req_r[i], sram_wr_resp_s[i]);
    } (());

    (cmdordata_in, decompressed_output,
     sram_rd_req_s, sram_rd_resp_r,
     sram_wr_req_s, sram_wr_resp_r)
  }

  next(tok: token, state: SnappyCommandExecuterState) {
    let (tok, cmdordata, recv_valid) = recv_if_non_blocking(tok,
      cmdordata_in,
     state.recv_cmdordata_ready,
     zero!<SnpyCmdOrData>());

    let state = if (recv_valid && state.recv_cmdordata_ready) {
      SnappyCommandExecuterState {
        recv_cmdordata_valid: true,
        recv_cmdordata_ready: false,
        cmdordata: cmdordata
        ..state
      }
    } else {
      state
    };

    let (history_update, history_lookup, state) = match state.fsm {
      CommandExecuterFSM::SET_COMMAND =>
        set_command(state),
      CommandExecuterFSM::SHIP_LITERALS =>
        ship_literals(state),
      CommandExecuterFSM::PERFORM_COPY =>
        perform_copy(state),
      _ => (false, false, state)
    };

    let (tok, state) = if (history_update) {
      assert_eq(state.cmdordata.is_cmd, false);
      assert_eq(state.cur_cmd.is_copy, false);

      let data = state.cmdordata.data;
      let valid_bytes = data.valid_bytes;
      let sram_bank_start_idx = state.historybuffer_ptr % BUS_BYTES;

      // perform writes to SRAM
      let tok = for (idx, tok): (u32, token) in range(u32:0, BUS_BYTES) {
        let sram_bank_idx  = (sram_bank_start_idx + idx) % BUS_BYTES;
        let sram_bank_addr = (state.historybuffer_ptr + idx) >> BUS_BYTES;
        let byte_mask = (u32:1 << 8) - u32:1;
        let sram_write_data = (data.data >> (u32:8 * idx)) & byte_mask;

        if (idx < valid_bytes) {
          send(tok,
              sram_wr_req_s[sram_bank_idx],
              WriteReq {
          addr: sram_bank_addr,
          data: sram_write_data
          });
        } else {
          tok
        };
        let (tok, _) = recv(tok, sram_wr_resp_r);
        tok
      } (tok);

      // perform writes to output
      let tok = send(tok, decompressed_output, data);

      // update state
      let cur_lit_done = (state.cur_litlen_shipped + valid_bytes) >= state.cur_cmd.lit_info.litlen;
      let (nxt_cur_litlen_shipped, fsm) = if cur_lit_done {
        (u32:0, CommandExecuterFSM::SET_COMMAND)
      } else {
        (state.cur_litlen_shipped + valid_bytes, CommandExecuterFSM::SHIP_LITERALS)
      };
      let new_state = SnappyCommandExecuterState {
        fsm: fsm,
        recv_cmdordata_valid: false,
        recv_cmdordata_ready: true,
        historybuffer_ptr: state.historybuffer_ptr + valid_bytes,
        cur_litlen_shipped: nxt_cur_litlen_shipped,
        ..state
      };
      (tok, new_state)
    } else if (history_lookup) {
      assert_eq(state.cmdordata.is_cmd, true);

      (tok, ???)
    } else {
      (tok, false, zero!<DataBundle>(), state)
    };
  }
}
