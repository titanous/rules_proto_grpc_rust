load("//rules/proto/connect_web:connect_web_library.bzl", _connect_web_library = "connect_web_library_macro")
load("//rules/proto/rust:tonic_library.bzl", _tonic_library = "tonic_library")

connect_web_library = _connect_web_library
tonic_library = _tonic_library
