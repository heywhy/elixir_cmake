defmodule Mix.Tasks.Compile.ElixirCmake do
  @moduledoc """
    Runs `make` in the current project.

    This task runs `make` in the current project; any output coming from `make` is
    printed in real-time on stdout.
  """

  use Mix.Task

  alias ElixirCMake.Compiler
  alias Mix.Project

  @doc false
  @impl Mix.Task
  def run(args) do
    Mix.shell().print_app()
    Project.ensure_structure()

    priv? = File.dir?("priv")

    config = Mix.Project.config()

    config
    |> merge_mix_env()
    |> Compiler.compile!(args)

    # IF there was no priv before and now there is one, we assume
    # the user wants to copy it. If priv already existed and was
    # written to it, then it won't be copied if build_embedded is
    # set to true.
    if not priv? and File.dir?("priv") do
      Project.build_structure()
    end

    :ok
  end

  defp merge_mix_env(config) do
    defaults = %{
      "MIX_ENV" => Atom.to_string(Mix.env()),
      "MIX_TARGET" => Atom.to_string(Mix.target()),
      "MIX_BUILD_PATH" => Project.build_path(config),
      "MIX_APP_PATH" => Project.app_path(config),
      "MIX_COMPILE_PATH" => Project.compile_path(config),
      "MIX_CONSOLIDATION_PATH" => Project.consolidation_path(config),
      "MIX_DEPS_PATH" => Project.deps_path(config),
      "MIX_MANIFEST_PATH" => Project.manifest_path(config)
    }

    env =
      case config[:cmake_env] do
        nil -> %{}
        env when is_map(env) -> env
        fun when is_function(fun) -> fun.()
      end

    defaults
    |> Map.merge(env)
    |> then(&Keyword.put(config, :cmake_env, &1))
  end
end
