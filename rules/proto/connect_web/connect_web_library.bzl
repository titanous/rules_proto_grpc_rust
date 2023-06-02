load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "@rules_proto_grpc//:defs.bzl",
    "ProtoCompileInfo",
    "ProtoPluginInfo",
    "bazel_build_rule_common_attrs",
    "proto_compile_attrs",
    "proto_compile_impl",
)

# based on https://github.com/aspect-build/rules_js/issues/397
connect_web_compile = rule(
    implementation = proto_compile_impl,
    attrs = dict(
        proto_compile_attrs,
        _plugins = attr.label_list(
            providers = [ProtoPluginInfo],
            default = [
                Label("//rules/proto/connect_web:connect_web_compile"),
            ],
            doc = "List of protoc plugins to apply",
        ),
    ),
    toolchains = [
        str(Label("@rules_proto_grpc//protobuf:toolchain_type")),
    ],
)

es_compile = rule(
    implementation = proto_compile_impl,
    attrs = dict(
        proto_compile_attrs,
        _plugins = attr.label_list(
            providers = [ProtoPluginInfo],
            default = [
                Label("//rules/proto/connect_web:es_compile"),
            ],
            doc = "List of protoc plugins to apply",
        ),
    ),
    toolchains = [
        str(Label("@rules_proto_grpc//protobuf:toolchain_type")),
    ],
)

def _connect_web_indexes(ctx):
    in_dirs = []
    for s in ctx.attr.srcs:
        in_dirs.append(s[ProtoCompileInfo].output_dirs.to_list()[0])

    out_dir = ctx.actions.declare_directory(ctx.label.name)
    ctx.actions.run(
        outputs = [out_dir],
        inputs = in_dirs,
        executable = ctx.executable._script,
        arguments = [out_dir.path] + [d.path for d in in_dirs],
    )

    return [DefaultInfo(
        files = depset([out_dir]),
    )]

connect_web_indexes = rule(
    implementation = _connect_web_indexes,
    attrs = dict(
        srcs = attr.label_list(
            providers = [ProtoCompileInfo],
            mandatory = True,
        ),
        _script = attr.label(
            default = Label("//rules/proto/connect_web:build_indexes"),
            executable = True,
            cfg = "exec",
        ),
    ),
)

def connect_web_library_macro(name, **kwargs):
    name_pb = name + "_pb"
    es_compile(
        name = name_pb,
        **{
            k: v
            for (k, v) in kwargs.items()
            if k in proto_compile_attrs.keys() or
               k in bazel_build_rule_common_attrs
        }  # Forward args
    )

    name_connectweb = name + "_connectweb"
    connect_web_compile(
        name = name_connectweb,
        **{
            k: v
            for (k, v) in kwargs.items()
            if k in proto_compile_attrs.keys() or
               k in bazel_build_rule_common_attrs
        }  # Forward args
    )

    name_indexes = name + "_indexes"
    connect_web_indexes(
        name = name_indexes,
        srcs = [name_pb, name_connectweb],
    )

    package_name = kwargs.get("package_name", name)
    package_json = name + "_package_json"
    write_file(
        name = package_json,
        out = name + "_pkg/package.json",
        content = [json.encode({
            "name": package_name,
            "private": True,
            "type": "module",
        })],
    )

    name_lib = name + "_lib"
    js_library(
        name = name_lib,
        srcs = [name_pb, name_connectweb, name_indexes, package_json],
        deps = ["//:node_modules/@bufbuild/connect-web", "//:node_modules/@bufbuild/protobuf"] + kwargs.get("deps", []),
        **{
            k: v
            for (k, v) in kwargs.items()
            if k in bazel_build_rule_common_attrs
        }  # Forward Bazel common args
    )

    npm_package(
        name = name,
        srcs = [name_lib],
        package = package_name,
        replace_prefixes = {
            name + "_pkg": "",
            name_connectweb: "",
            name_pb: "",
            name_indexes: "",
        },
        tags = ["codegen"],
    )
