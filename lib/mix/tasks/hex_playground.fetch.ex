defmodule Mix.Tasks.HexPlayground.Fetch do
  use Mix.Task

  @shortdoc "Fetch and extract a Hex.pm source corpus"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    HexPlayground.CLI.main(["fetch" | args])
  end
end
