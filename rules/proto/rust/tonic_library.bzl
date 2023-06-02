load(":fixer.bzl", "proto_crate_fixer", "proto_crate_root")
load("@rules_rust//rust:defs.bzl", "rust_library")
load(
    "@rules_proto_grpc//:defs.bzl",
    "ProtoCompileInfo",
    "ProtoPluginInfo",
    "bazel_build_rule_common_attrs",
    "proto_compile_attrs",
    "proto_compile_impl",
)

tonic_compile = rule(
    implementation = proto_compile_impl,
    attrs = dict(
        proto_compile_attrs,
        _plugins = attr.label_list(
            providers = [ProtoPluginInfo],
            default = [
                Label("//rules/proto/rust:prost_plugin"),
                Label("//rules/proto/rust:serde_plugin"),
                Label("//rules/proto/rust:tonic_plugin"),
                Label("//rules/proto/rust:any_plugin"),
                Label("//rules/proto/rust:crate_plugin"),
            ],
            doc = "List of protoc plugins to apply",
        ),
    ),
    toolchains = [
        str(Label("@rules_proto_grpc//protobuf:toolchain_type")),
    ],
)

def tonic_library(name, **kwargs):
    # Compile protos
    name_pb = name + "_pb"
    name_fixed = name_pb + "_fixed"
    name_root = name + "_root"
    tonic_compile(
        name = name_pb,
        **{
            k: v
            for (k, v) in kwargs.items()
            if k in proto_compile_attrs.keys() or
               k in bazel_build_rule_common_attrs
        }  # Forward args
    )

    # fix up imports
    proto_crate_fixer(
        name = name_fixed,
        compilation = name_pb,
        tags = ["codegen"],
    )

    proto_crate_root(
        name = name_root,
        crate_dir = name_fixed,
        tags = ["codegen"],
    )

    rust_library(
        name = name,
        edition = "2021",
        crate_root = name_root,
        crate_name = kwargs.get("crate_name"),
        srcs = [name_fixed],
        deps = [
            "//pkg/rs/prost_any",
            "@crate_index//:prost",
            "@crate_index//:tonic",
            "@crate_index//:serde",
            "@crate_index//:pbjson",
            "@crate_index//:pbjson-types",
            "@crate_index//:static_init",
        ],
        proc_macro_deps = ["@crate_index//:prost-derive"],
        **{
            k: v
            for (k, v) in kwargs.items()
            if k in bazel_build_rule_common_attrs
        }  # Forward Bazel common args
    )
