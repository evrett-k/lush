-- Lua Integration Test
print("Running Lua tests...")
print("Filesystem Builtins")
mkdir("lua_test")
touch("lua_test/file.txt")
ls("lua_test")
rm("lua_test/file.txt")
rm("lua_test")

print("Lua Logic")
print("test-finished")
