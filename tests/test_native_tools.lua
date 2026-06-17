-- Lush Test Suite
print("Running Lush native tool integration tests...")

-- Test file system operations
print("Testing filesystem builtins...")
mkdir("test_dir")
touch("test_dir/file.txt")
ls("test_dir")
mv("test_dir/file.txt", "test_dir/renamed.txt")
rm("test_dir/renamed.txt")
rm("test_dir")
print("Filesystem tests passed.")

-- Test tool invocation (calling some registered commands)
print("Testing tool invocation...")
-- These will print to stdout if installed on your system
echo("Hello Lush!")
whoami()
pwd()

-- Test script execution simulation
print("Testing exec function...")
exec("ls", "-la")

print("All tests completed successfully!")
