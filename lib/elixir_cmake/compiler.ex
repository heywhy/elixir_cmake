defmodule ElixirCMake.Compiler do
  @error_msg "You need to have cmake installed"

  @spec compile!(keyword(), list()) :: :ok
  def compile!(config, args) do
    cmake(config, args)
  end

  defp cmake(config, args) do
    cwd = File.cwd!()
    verbose? = "--verbose" in args
    env = merge_erl_env(config[:cmake_env])
    exec = System.get_env("CMAKE") || "cmake"

    build_dir = project_build_dir(config)
    custom_args = Keyword.get(config, :cmake_args, [])
    args = ["-B", build_dir] ++ custom_args

    with 0 <- cmd(exec, args, cwd, env, verbose?),
         0 <- cmd(exec, ["--build", build_dir], cwd, env, verbose?) do
      :ok
    else
      status -> raise_build_error(exec, status, @error_msg)
    end
  end

  # Runs `exec [args]` in `cwd` and prints the stdout and stderr in real time,
  # as soon as `exec` prints them (using `IO.Stream`).
  defp cmd(exec, args, cwd, env, verbose?) do
    opts = [
      # There is no guarantee the command will return valid UTF-8,
      # especially on Windows, so don't try to interpret the stream
      into: IO.binstream(:stdio, :line),
      stderr_to_stdout: true,
      cd: cwd,
      env: env
    ]

    if verbose? do
      print_verbose_info(exec, args)
    end

    {%IO.Stream{}, status} = System.cmd(find_executable(exec), args, opts)
    status
  end

  defp find_executable(exec) do
    System.find_executable(exec) ||
      Mix.raise("""
      "#{exec}" not found in the path. If you have set the CMAKE environment variable, \
      please make sure it is correct.
      """)
  end

  @dialyzer {:nowarn_function, raise_build_error: 3}
  defp raise_build_error(exec, exit_status, error_msg) do
    Mix.raise(~s{Could not compile with "#{exec}" (exit status: #{exit_status}).\n} <> error_msg)
  end

  defp print_verbose_info(exec, args) do
    args =
      Enum.map_join(args, " ", fn arg ->
        if String.contains?(arg, " "), do: inspect(arg), else: arg
      end)

    Mix.shell().info("Compiling with cmake: #{exec} #{args}")
  end

  defp project_build_dir(config) do
    config
    |> Keyword.get(:cmake_build_dir, "build")
    |> Path.expand(File.cwd!())
    |> tap(&make_dir!/1)
  end

  defp make_dir!(dir) do
    case File.dir?(dir) do
      true -> :ok
      false -> File.mkdir!(dir)
    end
  end

  # Returns a map of default environment variables
  # Defaults may be overwritten.
  defp merge_erl_env(nil), do: merge_erl_env(%{})
  defp merge_erl_env(fun) when is_function(fun), do: merge_erl_env(fun.())

  defp merge_erl_env(overrides) do
    root_dir = :code.root_dir()
    erl_interface_dir = Path.join(root_dir, "usr")
    erts_dir = Path.join(root_dir, "erts-#{:erlang.system_info(:version)}")
    erts_include_dir = Path.join(erts_dir, "include")
    erl_ei_lib_dir = Path.join(erl_interface_dir, "lib")
    erl_ei_include_dir = Path.join(erl_interface_dir, "include")

    Map.merge(
      %{
        # Rebar naming
        "ERL_EI_LIBDIR" => env("ERL_EI_LIBDIR", erl_ei_lib_dir),
        "ERL_EI_INCLUDE_DIR" => env("ERL_EI_INCLUDE_DIR", erl_ei_include_dir),

        # erlang.mk naming
        "ERTS_INCLUDE_DIR" => env("ERTS_INCLUDE_DIR", erts_include_dir),
        "ERL_INTERFACE_LIB_DIR" => env("ERL_INTERFACE_LIB_DIR", erl_ei_lib_dir),
        "ERL_INTERFACE_INCLUDE_DIR" => env("ERL_INTERFACE_INCLUDE_DIR", erl_ei_include_dir),

        # Disable default erlang values
        "BINDIR" => nil,
        "ROOTDIR" => nil,
        "PROGNAME" => nil,
        "EMU" => nil
      },
      overrides
    )
  end

  defp env(var, default), do: System.get_env(var) || default
end
