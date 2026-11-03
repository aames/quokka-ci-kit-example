import importlib.metadata
import platform
import sys


def test_arithmetic():
    assert 1 + 1 == 2


def test_the_interpreter_is_the_pinned_one():
    assert platform.python_version() == "3.12.15"


def test_it_is_the_standalone_build_not_the_base_images_own_python3():
    assert sys.base_prefix == "/usr/local/python"


def test_pip_installed_what_the_hashed_file_names():
    assert importlib.metadata.version("pytest") == "9.2.0"
