
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
    name = "snappy_libs_dslx",
    srcs = [
        "buffer.x",
        "common.x",
        "varint.x",
        "snappy.x"
    ]
)

xls_dslx_opt_ir(
    name = "snappy_opt_ir",
    dslx_top = "Snappy",
    library = "snappy_libs_dslx"
)
