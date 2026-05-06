defmodule HexPlayground.Registry do
  @moduledoc false

  alias HexPlayground.HTTP

  @api_packages "https://hex.pm/api/packages"

  def versions(registry_url, _timeout) do
    config = hex_config(registry_url)

    case :hex_repo.get_versions(config) do
      {:ok, {200, _headers, %{packages: packages}}} ->
        packages

      {:ok, {status, _headers, body}} ->
        raise "GET #{registry_url}/versions failed with #{status}: #{inspect(body)}"

      {:error, reason} ->
        raise "GET #{registry_url}/versions failed: #{inspect(reason)}"
    end
  end

  def top(limit, timeout) do
    Stream.iterate(1, &(&1 + 1))
    |> Enum.reduce_while([], fn page, acc ->
      batch = get_json!("#{@api_packages}?sort=downloads&page=#{page}", timeout)
      next = acc ++ batch

      cond do
        length(next) >= limit -> {:halt, Enum.take(next, limit)}
        batch == [] -> {:halt, next}
        true -> {:cont, next}
      end
    end)
    |> Enum.map(fn pkg ->
      %{
        name: pkg["name"],
        version: pkg["latest_stable_version"] || pkg["latest_version"],
        downloads: pkg["downloads"],
        html_url: pkg["html_url"],
        docs_html_url: pkg["docs_html_url"],
        package_api_url: pkg["url"]
      }
    end)
  end

  def select(packages, "all", limit) do
    packages
    |> Enum.flat_map(fn %{name: name, versions: versions} ->
      Enum.map(versions, &%{name: to_string(name), version: to_string(&1)})
    end)
    |> maybe_limit(limit)
  end

  def select(packages, "latest", limit) do
    packages
    |> Enum.map(fn %{name: name, versions: versions} ->
      %{name: to_string(name), version: latest_version(versions)}
    end)
    |> maybe_limit(limit)
  end

  def select(_packages, mode, _limit), do: raise("unknown mode #{inspect(mode)}")

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, limit), do: Enum.take(entries, limit)

  defp latest_version(versions) do
    versions
    |> Enum.map(&to_string/1)
    |> Enum.reduce(fn version, latest ->
      case Version.compare(version, latest) do
        :gt -> version
        _ -> latest
      end
    end)
  end

  defp hex_config(registry_url) do
    :hex_core.default_config()
    |> Map.put(:repo_url, registry_url)
    |> Map.put(:http_user_agent_fragment, <<"(hex_playground/0.1.0)">>)
  end

  defp get_json!(url, timeout) do
    %{body: body} = HTTP.get!(url, timeout: timeout)
    body
  end
end
