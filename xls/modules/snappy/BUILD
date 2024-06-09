
load(
    "//third_party/xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_opt_ir",
    "xls_dslx_test",
    "xls_dslx_verilog",
)

package(
    default_applicable_licenses = ["//third_party/xls:license"],
    default_visibility = ["//third_party/xls:xls_users"],
    licenses = ["notice"],
)

xls_dslx_library(
    name = "buffer_dslx",
    srcs = [
        "buffer.x",
    ]
)

xls_dslx_test(
    name = "buffer_test",
    dslx_test_args = {
        "compare": "none"
    },
    library = ":buffer_dslx"
)

xls_dslx_library(
    name = "snappy_common_dslx",
    srcs = [
        "buffer.x",
        "common.x",
        "varint.x",
    ]
)

xls_dslx_library(
    name = "snappy_submodules_dslx",
    srcs = [
        "command_expander.x",
        "copy_splitter.x",
        "command_executer.x",
    ],
    deps = [
        ":snappy_common_dslx",
        "//third_party/xls/examples:ram_dslx",
    ]
)

xls_dslx_library(
    name = "snappy_decomp_dslx",
    srcs = [
        "snappy.x",
    ],
    deps = [
        ":snappy_common_dslx",
        ":snappy_submodules_dslx",
        "//third_party/xls/examples:ram_dslx",
    ]
)

xls_dslx_test(
    name = "snappy_decomp_test",
    dslx_test_args = {
    },
    library = ":snappy_decomp_dslx"
)

xls_dslx_verilog(
    name = "snappy_decompressor_verilog",
    codegen_args = {
        "module_name": "SnappyDecompressor",
        "delay_model": "asap7",
        "pipeline_stages": "2",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    dslx_top = "SnappyDecompressor",
    library = ":snappy_decomp_dslx",
    verilog_file = "snappy_decompressor.v"
)

filegroup(
  name = "x_files",
  srcs = glob(["*.x"]),
  visibility = ["//third_party/xls/xls_internal"]
)

