def _mes_tool_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name)

    # There is a {rulename}.runfiles directory adjacent to the tool's
    # executable file which contains all runfiles. This is not guaranteed
    # to be relative to the directory in which the executable file is run.
    runfiles_path = "$0.runfiles/"

    # Each runfile under the runfiles path resides under a directory with
    # with the same name as its workspace.
    data_file_root = runfiles_path + ctx.workspace_name + "/"

    data_file_path = data_file_root + ctx.files.module[0].path

    my_runfiles = ctx.runfiles(
        files = ctx.files.module,
    )

     # Even root symlinks are under the runfiles path.
    data_dep_path = runfiles_path + "data_dep"

     # Create the output executable file with command as its content.
    ctx.actions.write(
        output = ctx.outputs.executable,
        # Simple example, effectively puts the contents of data.txt into
        # the output twice (read once via symlink, once via normal file).
        content = "#!/usr/bin/env bash\ncat %s %s > $1" % (data_file_path, data_dep_path),
        is_executable = True,
    )

    return [DefaultInfo(
        # The tool itself should just declare `runfiles`. The build
        # system will automatically create a `files_to_run` object
        # from the result of this declaration (used later).
        runfiles = my_runfiles,
    )]

mes_tool = rule(
    implementation = _mes_tool_impl,
    executable = True,
    attrs = {
        "module": attr.label(
            allow_files = True,
            default = "@mes-m2//:module_files",
        ),
        "compiler": attr.label(
            executable = True,
            cfg = "exec",
            doc = "The mes assembler.",
            default = "@//tools/mes:mes-m2-internal",
        ),
    },
)
