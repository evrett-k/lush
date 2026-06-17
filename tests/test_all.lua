#!/usr/bin/env lush
print("master test suite")

-- test.lush
print("testing tests/test.lush")
rc1 = exec("./target/debug/lush", "tests/test.lush")
if rc1 == 0 then print("  ✓ tests/test.lush") else print("  ✗ tests/test.lush") end

-- test.lua
print("testing tests/test.lua")
rc2 = exec("./target/debug/lush", "tests/test.lua")
if rc2 == 0 then print("  ✓ tests/test.lua") else print("  ✗ tests/test.lua") end

-- test_native_tools.lua
print("testing tests/test_native_tools.lua")
rc4 = exec("./target/debug/lush", "tests/test_native_tools.lua")
if rc4 == 0 then print("  ✓ tests/test_native_tools.lua") else print("  ✗ tests/test_native_tools.lua") end

-- test.sh
print("testing tests/test.sh")
rc3 = exec("./target/debug/lush", "tests/test.sh")
if rc3 == 0 then print("  ✓ tests/test.sh") else print("  ✗ tests/test.sh") end

print("done")
