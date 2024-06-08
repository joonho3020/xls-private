
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;
import xls.examples.ram;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:50;

const SNAPPY_MAX_HISTORY_BYTES = common::SNAPPY_MAX_HISTORY_BYTES;
const SRAM_WORD_BITS = BYTE;
const SRAM_WORD_CNT = SNAPPY_MAX_HISTORY_BYTES / BUS_BYTES;
const SRAM_WORD_MASK = BYTE;
const SRAM_RW_BEHAVIOR = ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
const SRAM_NUM_PARTITIONS = u32:1;
// (SRAM_WORD_MASK + SRAM_WORD_BITS - u32:1) / SRAM_WORD_MASK;
const SRAM_INIT = true;
const SRAM_ADDR_BITS = u32:12;
// std::clog2(SRAM_WORD_CNT);
// type WriteReq = ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>;
// type WriteWordReq = ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>;
// type WriteResp = ram::WriteResp;
// type ReadReq = ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>;
// type ReadWordReq = ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>;
type ReadResp = ram::ReadResp<SRAM_WORD_BITS>;

type RotBuffer = buff::RotBuffer<BUFFER_BITS>;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;
type uBusBits = uN[BUS_BITS];

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
  cur_cmd: SnpyCmd,
  cmdordata: SnpyCmdOrData,
  historybuffer_ptr: u32, // assume filesizes <= 4GB
  cur_litlen_shipped: u32,
  cur_copy_databundle: DataBundle
}

pub fn set_command(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  assert_eq(state.cmdordata.is_cmd, true);
  let (history_lookup, next_fsm) = if (state.cmdordata.cmd.is_copy) {
    (true, CommandExecuterFSM::PERFORM_COPY)
  } else {
    (false, CommandExecuterFSM::SHIP_LITERALS)
  };
  let next_state = SnappyCommandExecuterState {
    fsm: next_fsm,
    cur_cmd: state.cmdordata.cmd,
    ..state
  };
  (false, history_lookup, next_state)
}

pub fn ship_literals(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  (true, false, state)
}

pub fn perform_copy(state: SnappyCommandExecuterState) ->
    (bool, bool, SnappyCommandExecuterState) {
  (false, true, state)
}

proc SnappyCommandExecuter {
  cmdordata_in: chan<SnpyCmdOrData> in;
  decompressed_output: chan<DataBundle> out;

  sram_rd_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>[BUS_BYTES] out;
  sram_rd_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>>[BUS_BYTES] in;
  sram_wr_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>[BUS_BYTES] out;
  sram_wr_resp_r: chan<ram::WriteResp>[BUS_BYTES] in;

  init {
    (zero!<SnappyCommandExecuterState>())
  }

  config(cmdordata_in: chan<SnpyCmdOrData> in,
         decompressed_output: chan<DataBundle> out) {
    let (sram_rd_req_s, sram_rd_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>[BUS_BYTES]("sram_rd_req");
    let (sram_rd_resp_s, sram_rd_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>[BUS_BYTES]("sram_rd_resp");
    let (sram_wr_req_s, sram_wr_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>[BUS_BYTES]("sram_wr_req");
    let (sram_wr_resp_s, sram_wr_resp_r) = chan<ram::WriteResp>[BUS_BYTES]("sram_wr_resp");

    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[0], sram_rd_resp_s[0],
        sram_wr_req_r[0], sram_wr_resp_s[0]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[1], sram_rd_resp_s[1],
        sram_wr_req_r[1], sram_wr_resp_s[1]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[2], sram_rd_resp_s[2],
        sram_wr_req_r[2], sram_wr_resp_s[2]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[3], sram_rd_resp_s[3],
        sram_wr_req_r[3], sram_wr_resp_s[3]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[4], sram_rd_resp_s[4],
        sram_wr_req_r[4], sram_wr_resp_s[4]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[5], sram_rd_resp_s[5],
        sram_wr_req_r[5], sram_wr_resp_s[5]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[6], sram_rd_resp_s[6],
        sram_wr_req_r[6], sram_wr_resp_s[6]);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd_req_r[7], sram_rd_resp_s[7],
        sram_wr_req_r[7], sram_wr_resp_s[7]);

    // for (i, _) : (u32, ()) in range(u32:0, BUS_BYTES) {
    //   spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
    //     SRAM_RW_BEHAVIOR, SRAM_INIT> (
    //       sram_rd_req_r[i], sram_rd_resp_s[i],
    //       sram_wr_req_r[i], sram_wr_resp_s[i]);
    // } (());

    (cmdordata_in, decompressed_output,
     sram_rd_req_s, sram_rd_resp_r,
     sram_wr_req_s, sram_wr_resp_r)
  }

  next(tok: token, state: SnappyCommandExecuterState) {
    let (tok, cmdordata) = recv(tok, cmdordata_in);

    trace_fmt!("[SnpyCommandExecuter] recv {:x}", cmdordata);

    let state = SnappyCommandExecuterState {
      cmdordata: cmdordata,
      ..state
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

    trace_fmt!("[SnpyCommandExecuter] history update {} history lookup {}",
      history_update, history_lookup);

    let (tok, state) = if (history_update) {
      assert_eq(state.cmdordata.is_cmd, false);
      assert_eq(state.cur_cmd.is_copy, false);

      let data = state.cmdordata.data;
      let valid_bytes = data.valid_bytes;
      let sram_bank_start_idx = state.historybuffer_ptr % BUS_BYTES;

      // TODO : Is this the correct way to perform parallel SRAM lookups?
      // perform writes to SRAM
      let tok = for (idx, tok): (u32, token) in range(u32:0, BUS_BYTES) {
        let sram_bank_idx  = (sram_bank_start_idx + idx) % BUS_BYTES;
        let historybuffer_offset = (state.historybuffer_ptr + idx) % SNAPPY_MAX_HISTORY_BYTES;
        let sram_bank_addr = historybuffer_offset >> std::clog2(BUS_BYTES);
        let byte_mask = (u32:1 << 8) - u32:1;
        let sram_write_data = (data.data >> (u32:8 * idx)) & byte_mask as uBusBits;

        let tok = if (idx < valid_bytes) {
          trace_fmt!("[SnpyCommandExecuter] SRAM WR LIT hb_offset {} bank {} addr {} data 0x{:x}",
                     historybuffer_offset, sram_bank_idx, sram_bank_addr, sram_write_data);
          let tok = send(tok,
              sram_wr_req_s[sram_bank_idx],
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv(tok, sram_wr_resp_r[sram_bank_idx]);
          tok
        } else {
          tok
        };
        join(tok, tok)
      } (tok);

      // perform writes to output
      let tok = send(tok, decompressed_output, data);
      trace_fmt!("[SnpyCommandExecuter] send lit decomp data {:x}", data);

      // update state
      let cur_lit_done = (state.cur_litlen_shipped + valid_bytes) >= state.cur_cmd.lit_info.litlen;
      let (nxt_cur_litlen_shipped, fsm) = if cur_lit_done {
        (u32:0, CommandExecuterFSM::SET_COMMAND)
      } else {
        (state.cur_litlen_shipped + valid_bytes, CommandExecuterFSM::SHIP_LITERALS)
      };
      let new_state = SnappyCommandExecuterState {
        fsm: fsm,
        historybuffer_ptr: state.historybuffer_ptr + valid_bytes,
        cur_litlen_shipped: nxt_cur_litlen_shipped,
        ..state
      };
      trace_fmt!("[SnpyCommandExecuter] cur_lit_done {} nxt_cur_litlen_shipped {} nxt_fsm {} nxt_hb_ptr {}",
                 cur_lit_done, nxt_cur_litlen_shipped, fsm, new_state.historybuffer_ptr);
      (tok, new_state)
    } else if (history_lookup) {
      assert_eq(state.cmdordata.is_cmd, true);
      assert_eq(state.cmdordata.cmd.is_copy, true);
      assert_eq(state.historybuffer_ptr - state.cmdordata.cmd.copy_info.offset >= u32:0, true);

      let copy_info = state.cmdordata.cmd.copy_info;
      let historybuffer_offset_ptr = state.historybuffer_ptr - copy_info.offset;
      let sram_bank_start_idx = historybuffer_offset_ptr % BUS_BYTES;

      // TODO : Is this the correct way to perform parallel SRAM lookups?
      // perform reads from SRAM
      let (tok, state) = for (idx, (tok, state)): (u32, (token, SnappyCommandExecuterState)) in range(u32:0, BUS_BYTES) {
        let sram_bank_idx = (sram_bank_start_idx + idx) % BUS_BYTES;
        let historybuffer_offset = (historybuffer_offset_ptr + idx) % SNAPPY_MAX_HISTORY_BYTES;
        let sram_bank_addr = historybuffer_offset >> std::clog2(BUS_BYTES);

        let valid_copy = (idx < copy_info.copy_len);
        let (tok, read_data) = if (valid_copy) {
          let tok = send(tok, sram_rd_req_s[sram_bank_idx],
                      ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          recv(tok, sram_rd_resp_r[sram_bank_idx])
        } else {
          (tok, zero!<ReadResp>())
        };

        if (valid_copy) {
          trace_fmt!("[SnpyCommandExecuter] SRAM RD hb_offset{} bank {} addr {} data 0x{:x}",
            historybuffer_offset, sram_bank_idx, sram_bank_addr, read_data);
        } else {};

        let databundle = state.cur_copy_databundle;
        let valid_bytes_to_add = if (valid_copy) { u32:1 } else { u32:0 };
        let new_databundle = DataBundle {
          valid_bytes: databundle.valid_bytes + valid_bytes_to_add,
          data: ((read_data.data as uBusBits << (BYTE * idx)) as uBusBits) | databundle.data,
          is_last: state.cmdordata.is_last
        };
        let state = SnappyCommandExecuterState {
          cur_copy_databundle: new_databundle,
          ..state
        };
        (tok, state)
      } ((tok, state));

      trace_fmt!("[SnpyCommandExecuter] cur_copy_databundle {:x}",
        state.cur_copy_databundle);

      let data = state.cur_copy_databundle;
      let valid_bytes = data.valid_bytes;
      let sram_bank_start_idx = state.historybuffer_ptr % BUS_BYTES;

      // TODO : Is this the correct way to perform parallel SRAM lookups?
      // perform writes to SRAM
      let tok = for (idx, tok): (u32, token) in range(u32:0, BUS_BYTES) {
        let sram_bank_idx  = (sram_bank_start_idx + idx) % BUS_BYTES;
        let historybuffer_offset = (state.historybuffer_ptr + idx) % SNAPPY_MAX_HISTORY_BYTES;
        let sram_bank_addr = historybuffer_offset >> std::clog2(BUS_BYTES);
        let byte_mask = (u32:1 << 8) - u32:1;
        let sram_write_data = (data.data >> (u32:8 * idx)) & byte_mask as uBusBits;

        let tok = if (idx < valid_bytes) {
          trace_fmt!("[SnpyCommandExecuter] SRAM WR COPY hb_offset {} bank {} addr {} data 0x{:x}",
                     historybuffer_offset, sram_bank_idx, sram_bank_addr, sram_write_data);
          let tok = send(tok,
              sram_wr_req_s[sram_bank_idx],
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv(tok, sram_wr_resp_r[sram_bank_idx]);
          tok
        } else {
          tok
        };
        join(tok, tok)
      } (tok);

      // perform writes to output
      let tok = send(tok, decompressed_output, state.cur_copy_databundle);
      let new_state = SnappyCommandExecuterState {
        fsm: CommandExecuterFSM::SET_COMMAND,
        historybuffer_ptr: state.historybuffer_ptr + valid_bytes,
        cur_copy_databundle: zero!<DataBundle>(),
        ..state
      };

      (tok, new_state)
    } else {
      (tok, state)
    };

    state
  }
}
