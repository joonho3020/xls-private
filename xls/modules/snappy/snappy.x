
import std;
import xls.modules.snappy.buffer as buff;
import xls.modules.snappy.common;
import xls.modules.snappy.varint as varint;
import xls.modules.snappy.command_expander as command_expander;

const BYTE     = common::BYTE;
const BUS_BITS = common::BUS_BITS;
const BUS_BYTES = BUS_BITS >> 3;
const BUFFER_BITS = BUS_BITS * u32:2;

type Buffer = buff::Buffer;
type BusBytesBundle = common::BusBytesBundle;
type DataBundle = common::DataBundle<BUS_BITS>;
type SnappyDecompInfo = common::SnappyDecompInfo;
type SnpyCmdOrData = common::SnpyCmdOrData<BUS_BITS>;

pub enum SnappyFSMStates : u2 {
  CONFIGURE_SNAPPY_ACCEL = 0,
  VARINT_DECODE = 1,
  DECOMPRESS = 2
}

struct SnappyState {
  buffer: Buffer<BUFFER_BITS>,
  varint_idx: u32,
  out_decomp_file_bytes: u32,
  in_comp_file_bytes: u32,
  bytes_sent: u32,
  fsm: SnappyFSMStates
}

fn snappy_varint_decode(state: SnappyState) -> (bool, DataBundle, SnappyState) {
  let (br, data) = buff::buffer_pop(state.buffer, BYTE);

  trace_fmt!("VARINT byte: {}", data);

  if br.status == buff::BufferStatus::FAILED {
    (false, zero!<DataBundle>(), state)
  } else {
    let vi = varint::decode_to_varint(data as u8);
    let varint_to_add = vi.data << ((state.varint_idx * u32:7) as u8);
    trace_fmt!("decoded varint {} {:x}", vi.more_bytes, vi.data);
    let nxt_fsm_state = if vi.more_bytes == u1:0 {
      SnappyFSMStates::DECOMPRESS
    } else {
      state.fsm
    };
    let new_state = SnappyState {
      buffer: br.buffer,
      varint_idx: state.varint_idx + u32:1,
      out_decomp_file_bytes: state.out_decomp_file_bytes + varint_to_add as u32,
      fsm: nxt_fsm_state,
      ..state
    };
    trace_fmt!("varint_idx: {} out_decomp_file_bytes: {} bytes", new_state.varint_idx, new_state.out_decomp_file_bytes);
    (false, zero!<DataBundle>(), new_state)
  }
}

fn snappy_feed_backend(state: SnappyState) -> (bool, DataBundle, SnappyState) {
  let remaining_bytes_to_send = state.in_comp_file_bytes - state.bytes_sent - state.varint_idx;
  let bytes_to_send_now = std::umin(remaining_bytes_to_send, BUS_BYTES);
  let bits_to_send_now = bytes_to_send_now << 3;
  let (buffer_result, bits_from_buffer) = buff::buffer_pop(state.buffer, bits_to_send_now);
  let is_last_chunk = remaining_bytes_to_send <= BUS_BYTES;

  trace_fmt!("[SnpyDecomp] bufbytes {} remaining_to_send {} bytes_to_send {} buff results {} is_last_chunk {}",
    state.buffer.length >> 3,
    remaining_bytes_to_send, bytes_to_send_now, buffer_result.status, is_last_chunk);
  if (buffer_result.status == buff::BufferStatus::OK) {
    (
      true,
      DataBundle {
        data: bits_from_buffer as bits[BUS_BITS],
        valid_bytes: bytes_to_send_now,
        is_last: is_last_chunk
      },
      SnappyState {
        buffer: buffer_result.buffer,
        bytes_sent: state.bytes_sent + bytes_to_send_now,
        ..state
      }
    )
  } else {
    (false, zero!<DataBundle>(), state)
  }
}

pub proc SnappyDecompressor {
  decomp_info_r: chan<SnappyDecompInfo> in;
  comp_data_r: chan<BusBytesBundle> in;
  databundle_s: chan<DataBundle> out;
  cmdordatabundle_r: chan<SnpyCmdOrData> in;
  done_s: chan<bool> out;

  init {
    (zero!<SnappyState>())
  }

  config (
    decomp_info_r: chan<SnappyDecompInfo> in,
    comp_data_r: chan<BusBytesBundle> in,
    done_s: chan<bool> out
  ) {
    let (databundle_s, databundle_r) = chan<DataBundle>("cmd_expander_in");
    let (cmdordatabundle_s, cmdordatabundle_r) = chan<SnpyCmdOrData>("cmd_expander_out");
    spawn command_expander::SnappyCommandExpander(databundle_r, cmdordatabundle_s);
    (decomp_info_r, comp_data_r, databundle_s, cmdordatabundle_r, done_s)
  }

  next (tok: token, state: SnappyState) {
    trace_fmt!("----------- SnappyDecompressor next -----------------");

    // Configure accelerator
    let configure = state.fsm == SnappyFSMStates::CONFIGURE_SNAPPY_ACCEL;
    let (tok, info, recv_valid) = recv_if_non_blocking(tok, decomp_info_r, configure, zero!<SnappyDecompInfo>());
    let state = if (configure && recv_valid) {
      trace_fmt!("[SnpyDecomp] Configuring.. compressed_file_bytes {}", info.compressed_file_bytes);
      SnappyState {
        in_comp_file_bytes: info.compressed_file_bytes,
        fsm: SnappyFSMStates::VARINT_DECODE,
        ..state
      }
    } else {
      state
    };

    // Continuously recv data from the input channel
    let can_fit = buff::buffer_can_fit(state.buffer, BusBytesBundle:0);
    trace_fmt!("[SnpyDecomp] can_fit {}", can_fit);
    let (tok, data, recv_valid) = recv_if_non_blocking(tok, comp_data_r, can_fit, BusBytesBundle:0);
    let state = if (can_fit && recv_valid) {
      trace_fmt!("[SnpyDecomp] RecvData {:x}", data);
      let buffer_result = buff::buffer_append(state.buffer, data);
      SnappyState {
        buffer: buffer_result.buffer,
        ..state
      }
    } else {
      state
    };

    let (do_send, data_to_send, state) = match state.fsm {
      SnappyFSMStates::VARINT_DECODE =>
        snappy_varint_decode(state),
      SnappyFSMStates::DECOMPRESS =>
        snappy_feed_backend(state),
      _ => (false, zero!<DataBundle>(), state)
    };

    let tok = if (do_send) {
      trace_fmt!("[SnpyDecomp] send to backend {:x}", data_to_send);
      send(tok, databundle_s, data_to_send)
    } else {
      tok
    };

    // let tok = if (do_send) {
    //   send(tok, done_s, true)
    // } else {
    //   tok
    // };

    state
  }
}

struct TestBenchState {
  sent_snappy_header: bool
}

#[test_proc]
proc SnappyDecompressorTest {
  terminator: chan<bool> out;
  decomp_info_s: chan<SnappyDecompInfo> out;
  comp_data_s: chan<BusBytesBundle> out;
  done_r: chan<bool> in;

  init {
    zero!<TestBenchState>()
  }

  config(terminator: chan<bool> out) {
    let (decomp_info_s, decomp_info_r) = chan<SnappyDecompInfo>("decomp_info");
    let (comp_data_s, comp_data_r) = chan<BusBytesBundle>("compressed");
    let (done_s, done_r) = chan<bool>("done");

    spawn SnappyDecompressor(decomp_info_r, comp_data_r, done_s);

    (terminator, decomp_info_s, comp_data_s, done_r)
  }

  next(tok: token, state: TestBenchState) {
    let (tok, state) = if (!state.sent_snappy_header) {
      let tok = send(
        tok,
        decomp_info_s,
        SnappyDecompInfo {
          compressed_file_bytes: u32:135
        });
      let tok = send(tok, comp_data_s, BusBytesBundle:0x70_61_6e_53_4c_f0_01_85);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x72_70_6d_6f_63_20_79_70);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x6f_66_20_64_65_73_73_65);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x73_65_64_20_74_61_6d_72);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x6e_6f_69_74_70_69_72_63);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x65_72_20_74_73_61_4c_0a);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x32_20_3a_64_65_73_69_76);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x30_2d_30_31_2d_31_31_30);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x69_20_73_69_68_54_0a_35);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x20_61_20_74_6f_6e_20_73);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x70_73_20_6c_28_3a_01_66);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x01_61_63_69_66_69_63_65);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x20_74_75_62_20_2c_90_3c);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x73_20_64_6c_75_6f_68_73);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x74_20_65_63_69_66_66_75);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x69_61_6c_70_78_65_20_6f);
      let tok = send(tok, comp_data_s, BusBytesBundle:0x74_73_6f_6d_20_6e_69);
      (
        tok,
        TestBenchState { sent_snappy_header: true }
      )
    } else {
      (tok, state)
    };

    let (tok, is_done, val) = recv_non_blocking(tok, done_r, false);
    let tok = if (is_done && val) {
      let tok = send(tok, terminator, true);
      tok
    } else {
      tok
    };
    state
  }
}
