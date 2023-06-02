"""Internal rules to fix up rust protoc output"""

load("@rules_proto_grpc//:defs.bzl", "ProtoCompileInfo")

def _proto_crate_root(ctx):
    name = ctx.attr.crate_dir
    lib_rs = ctx.actions.declare_file("%s_lib.rs" % name)
    ctx.actions.write(
        lib_rs,
        'include!("%s/mod.rs");' % name,
        False,
    )
    return [DefaultInfo(
        files = depset([lib_rs]),
    )]

def _proto_crate_fixer(ctx):
    """Fix up output, add include! for tonic/serde plugins"""

    compilation = ctx.attr.compilation[ProtoCompileInfo]
    in_dir = compilation.output_dirs.to_list()[0]
    out_dir = ctx.actions.declare_directory("%s_fixed" % compilation.label.name)

    ctx.actions.run(
        outputs = [out_dir],
        inputs = [in_dir],
        executable = ctx.executable._script,
        arguments = [in_dir.path, out_dir.path],
    )

    return [DefaultInfo(
        files = depset([out_dir]),
    )]

proto_crate_root = rule(
    implementation = _proto_crate_root,
    attrs = {
        "crate_dir": attr.string(
            mandatory = True,
        ),
    },
)

proto_crate_fixer = rule(
    implementation = _proto_crate_fixer,
    attrs = {
        "compilation": attr.label(
            providers = [ProtoCompileInfo],
            mandatory = True,
        ),
        "_script": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("//rules/proto/rust:fixer"),
        ),
    },
)
