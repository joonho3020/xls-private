
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
  // assert_eq(state.cmdordata.is_cmd, true);
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

  sram_rd0_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd0_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd1_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd1_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd2_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd2_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd3_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd3_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd4_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd4_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd5_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd5_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd6_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd6_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_rd7_req_s: chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_rd7_resp_r: chan<ram::ReadResp<SRAM_WORD_BITS>> in;

  sram_wr0_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr0_resp_r: chan<ram::WriteResp> in;

  sram_wr1_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr1_resp_r: chan<ram::WriteResp> in;

  sram_wr2_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr2_resp_r: chan<ram::WriteResp> in;

  sram_wr3_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr3_resp_r: chan<ram::WriteResp> in;

  sram_wr4_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr4_resp_r: chan<ram::WriteResp> in;

  sram_wr5_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr5_resp_r: chan<ram::WriteResp> in;

  sram_wr6_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr6_resp_r: chan<ram::WriteResp> in;

  sram_wr7_req_s: chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>> out;
  sram_wr7_resp_r: chan<ram::WriteResp> in;

  init {
    (zero!<SnappyCommandExecuterState>())
  }

  config(cmdordata_in: chan<SnpyCmdOrData> in,
         decompressed_output: chan<DataBundle> out) {
    let (sram_rd0_req_s, sram_rd0_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd0_req");
    let (sram_rd1_req_s, sram_rd1_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd1_req");
    let (sram_rd2_req_s, sram_rd2_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd2_req");
    let (sram_rd3_req_s, sram_rd3_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd3_req");
    let (sram_rd4_req_s, sram_rd4_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd4_req");
    let (sram_rd5_req_s, sram_rd5_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd5_req");
    let (sram_rd6_req_s, sram_rd6_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd6_req");
    let (sram_rd7_req_s, sram_rd7_req_r) = chan<ram::ReadReq<SRAM_ADDR_BITS, SRAM_NUM_PARTITIONS>>("sram_rd7_req");

    let (sram_rd0_resp_s, sram_rd0_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd0_resp");
    let (sram_rd1_resp_s, sram_rd1_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd1_resp");
    let (sram_rd2_resp_s, sram_rd2_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd2_resp");
    let (sram_rd3_resp_s, sram_rd3_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd3_resp");
    let (sram_rd4_resp_s, sram_rd4_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd4_resp");
    let (sram_rd5_resp_s, sram_rd5_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd5_resp");
    let (sram_rd6_resp_s, sram_rd6_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd6_resp");
    let (sram_rd7_resp_s, sram_rd7_resp_r) = chan<ram::ReadResp<SRAM_WORD_BITS>>("sram_rd7_resp");

    let (sram_wr0_req_s, sram_wr0_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr0_req");
    let (sram_wr1_req_s, sram_wr1_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr1_req");
    let (sram_wr2_req_s, sram_wr2_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr2_req");
    let (sram_wr3_req_s, sram_wr3_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr3_req");
    let (sram_wr4_req_s, sram_wr4_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr4_req");
    let (sram_wr5_req_s, sram_wr5_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr5_req");
    let (sram_wr6_req_s, sram_wr6_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr6_req");
    let (sram_wr7_req_s, sram_wr7_req_r) = chan<ram::WriteReq<SRAM_ADDR_BITS, SRAM_WORD_BITS, SRAM_NUM_PARTITIONS>>("sram_wr7_req");

    let (sram_wr0_resp_s, sram_wr0_resp_r) = chan<ram::WriteResp>("sram_wr0_resp");
    let (sram_wr1_resp_s, sram_wr1_resp_r) = chan<ram::WriteResp>("sram_wr1_resp");
    let (sram_wr2_resp_s, sram_wr2_resp_r) = chan<ram::WriteResp>("sram_wr2_resp");
    let (sram_wr3_resp_s, sram_wr3_resp_r) = chan<ram::WriteResp>("sram_wr3_resp");
    let (sram_wr4_resp_s, sram_wr4_resp_r) = chan<ram::WriteResp>("sram_wr4_resp");
    let (sram_wr5_resp_s, sram_wr5_resp_r) = chan<ram::WriteResp>("sram_wr5_resp");
    let (sram_wr6_resp_s, sram_wr6_resp_r) = chan<ram::WriteResp>("sram_wr6_resp");
    let (sram_wr7_resp_s, sram_wr7_resp_r) = chan<ram::WriteResp>("sram_wr7_resp");

    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd0_req_r, sram_rd0_resp_s,
        sram_wr0_req_r, sram_wr0_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd1_req_r, sram_rd1_resp_s,
        sram_wr1_req_r, sram_wr1_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd2_req_r, sram_rd2_resp_s,
        sram_wr2_req_r, sram_wr2_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd3_req_r, sram_rd3_resp_s,
        sram_wr3_req_r, sram_wr3_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd4_req_r, sram_rd4_resp_s,
        sram_wr4_req_r, sram_wr4_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd5_req_r, sram_rd5_resp_s,
        sram_wr5_req_r, sram_wr5_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd6_req_r, sram_rd6_resp_s,
        sram_wr6_req_r, sram_wr6_resp_s);
    spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
      SRAM_RW_BEHAVIOR, SRAM_INIT> (
        sram_rd7_req_r, sram_rd7_resp_s,
        sram_wr7_req_r, sram_wr7_resp_s);

    // for (i, _) : (u32, ()) in range(u32:0, BUS_BYTES) {
    //   spawn ram::RamModel<SRAM_WORD_BITS, SRAM_WORD_CNT, SRAM_WORD_MASK,
    //     SRAM_RW_BEHAVIOR, SRAM_INIT> (
    //       sram_rd_req_r[i], sram_rd_resp_s[i],
    //       sram_wr_req_r[i], sram_wr_resp_s[i]);
    // } (());

    (cmdordata_in, decompressed_output,
     sram_rd0_req_s, sram_rd0_resp_r,
     sram_rd1_req_s, sram_rd1_resp_r,
     sram_rd2_req_s, sram_rd2_resp_r,
     sram_rd3_req_s, sram_rd3_resp_r,
     sram_rd4_req_s, sram_rd4_resp_r,
     sram_rd5_req_s, sram_rd5_resp_r,
     sram_rd6_req_s, sram_rd6_resp_r,
     sram_rd7_req_s, sram_rd7_resp_r,
     sram_wr0_req_s, sram_wr0_resp_r,
     sram_wr1_req_s, sram_wr1_resp_r,
     sram_wr2_req_s, sram_wr2_resp_r,
     sram_wr3_req_s, sram_wr3_resp_r,
     sram_wr4_req_s, sram_wr4_resp_r,
     sram_wr5_req_s, sram_wr5_resp_r,
     sram_wr6_req_s, sram_wr6_resp_r,
     sram_wr7_req_s, sram_wr7_resp_r)
  }

  next(state: SnappyCommandExecuterState) {
    let (tok, cmdordata) = recv(token(), cmdordata_in);

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
      // assert_eq(state.cmdordata.is_cmd, false);
      // assert_eq(state.cur_cmd.is_copy, false);

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

          let tok = send_if(tok,
              sram_wr0_req_s,
              sram_bank_idx == u32:0,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr0_resp_r, sram_bank_idx == u32:0, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr1_req_s,
              sram_bank_idx == u32:1,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr1_resp_r, sram_bank_idx == u32:1, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr2_req_s,
              sram_bank_idx == u32:2,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr2_resp_r, sram_bank_idx == u32:2, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr3_req_s,
              sram_bank_idx == u32:3,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr3_resp_r, sram_bank_idx == u32:3, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr4_req_s,
              sram_bank_idx == u32:4,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr4_resp_r, sram_bank_idx == u32:4, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr5_req_s,
              sram_bank_idx == u32:5,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr5_resp_r, sram_bank_idx == u32:5, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr6_req_s,
              sram_bank_idx == u32:6,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr6_resp_r, sram_bank_idx == u32:6, zero!<ram::WriteResp>());

          let tok = send_if(tok,
              sram_wr7_req_s,
              sram_bank_idx == u32:7,
              ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
                sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          );
          let (tok, _) = recv_if(tok, sram_wr7_resp_r, sram_bank_idx == u32:7, zero!<ram::WriteResp>());

          // let tok = send(tok,
          //     sram_wr_req_s[sram_bank_idx],
          //     ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
          //       sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          // );
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
      // assert_eq(state.cmdordata.is_cmd, true);
      // assert_eq(state.cmdordata.cmd.is_copy, true);
      // assert_eq(state.historybuffer_ptr - state.cmdordata.cmd.copy_info.offset >= u32:0, true);

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
          send_if(tok, sram_rd0_req_s, sram_bank_idx == u32:0,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd1_req_s, sram_bank_idx == u32:1,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd2_req_s, sram_bank_idx == u32:2,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd3_req_s, sram_bank_idx == u32:3,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd4_req_s, sram_bank_idx == u32:4,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd5_req_s, sram_bank_idx == u32:5,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd6_req_s, sram_bank_idx == u32:6,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          send_if(tok, sram_rd7_req_s, sram_bank_idx == u32:7,
             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));

          let ret = if (sram_bank_idx == u32:0) {
            recv(tok, sram_rd0_resp_r)
          } else if (sram_bank_idx == u32:1) {
            recv(tok, sram_rd1_resp_r)
          } else if (sram_bank_idx == u32:2) {
            recv(tok, sram_rd2_resp_r)
          } else if (sram_bank_idx == u32:3) {
            recv(tok, sram_rd3_resp_r)
          } else if (sram_bank_idx == u32:4) {
            recv(tok, sram_rd4_resp_r)
          } else if (sram_bank_idx == u32:5) {
            recv(tok, sram_rd5_resp_r)
          } else if (sram_bank_idx == u32:6) {
            recv(tok, sram_rd6_resp_r)
          } else if (sram_bank_idx == u32:7) {
            recv(tok, sram_rd7_resp_r)
          } else {
            (tok, zero!<ReadResp>())
          };

          ret

          // let tok = send(tok, sram_rd_req_s[sram_bank_idx],
          //             ram::ReadWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS>(sram_bank_addr as uN[SRAM_ADDR_BITS]));
          // recv(tok, sram_rd_resp_r[sram_bank_idx])
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
          let tok = send_if(tok,
            sram_wr0_req_s, sram_bank_idx == u32:0,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr0_resp_r, sram_bank_idx == u32:0, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr1_req_s, sram_bank_idx == u32:1,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr1_resp_r, sram_bank_idx == u32:1, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr2_req_s, sram_bank_idx == u32:2,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr2_resp_r, sram_bank_idx == u32:2, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr3_req_s, sram_bank_idx == u32:3,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr3_resp_r, sram_bank_idx == u32:3, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr4_req_s, sram_bank_idx == u32:4,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr4_resp_r, sram_bank_idx == u32:4, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr5_req_s, sram_bank_idx == u32:5,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr5_resp_r, sram_bank_idx == u32:5, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr6_req_s, sram_bank_idx == u32:6,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr6_resp_r, sram_bank_idx == u32:6, zero!<ram::WriteResp>());

          let tok = send_if(tok,
            sram_wr7_req_s, sram_bank_idx == u32:7,
            ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
              sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS]));
          let (tok, _) = recv_if(tok, sram_wr7_resp_r, sram_bank_idx == u32:7, zero!<ram::WriteResp>());

          //let tok = send(tok,
          //    sram_wr_req_s[sram_bank_idx],
          //    ram::WriteWordReq<SRAM_NUM_PARTITIONS, SRAM_ADDR_BITS, SRAM_WORD_BITS>(
          //      sram_bank_addr as uN[SRAM_ADDR_BITS], sram_write_data as uN[SRAM_WORD_BITS])
          //);
          //let (tok, _) = recv(tok, sram_wr_resp_r[sram_bank_idx]);
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
