
ld -r -T link.lds --gc-sections --undefined AntkDriverEntry -z combreloc -nostdlib "$(cargo build --target x86_64-unknown-none -Zbuild-std=core --message-format=json-render-diagnostics "$@" | \
  jq -r 'select(.reason == "compiler-artifact" and .target.kind[] == "staticlib") | .filenames[] | select(endswith(".a"))')" -o ../../build/systemroot/test.drv