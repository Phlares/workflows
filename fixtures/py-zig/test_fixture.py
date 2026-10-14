import os
import pathlib

def test_env_input_reaches_tests():
    assert os.environ["FIXTURE_ENV"] == "ok"

def test_zig_step_ran_before_pytest():
    assert pathlib.Path("zig-out/hello.exe").is_file()
