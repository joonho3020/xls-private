
load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_opt_ir",
    "xls_dslx_test",
)

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_users"],
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
    name = "snappy_decomp_dslx",
    srcs = [
        "snappy.x",
        "command_expander.x",
        "copy_splitter.x",
        "command_executer.x",
    ],
    deps = [
        ":snappy_common_dslx",
        "//xls/examples:ram_dslx",
    ]
)

xls_dslx_test(
    name = "snappy_decomp_test",
    dslx_test_args = {
    },
    library = ":snappy_decomp_dslx"
)

# xls_dslx_opt_ir(
# name = "snappy_opt_ir",
# dslx_top = "SnappyDecompressor",
# library = "snappy_libs_dslx"
# )
