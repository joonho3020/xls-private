
# Running simulations
```bash
bazel run -- //xls/modules/snappy:snappy_decomp_test --alsologtostderr --compare=none > LOGS
```

# Verilog generation
```bash
bazel build --verbose_failures -- //xls/modules/snappy:snappy_decompressor_verilog
``

