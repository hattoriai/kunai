defmodule Kunai.Live.EndpointsLive do
  @moduledoc false
  # An owner's endpoints.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Kunai.Router

  import Kunai.Components

  @impl true
  def mount(_params, _session, socket) do
    page = Kunai.list_endpoints(socket.assigns.kunai_scope, limit: 100)
    {:ok, assign(socket, page_title: "Webhooks", endpoints: page.data, more?: page.has_more)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} flash={@flash} scope={@kunai_scope}>
      <.header title="Webhooks">
        <:subtitle>Endpoints that receive this account's events as they happen.</:subtitle>
        <:actions>
          <.button :if={@endpoints != []} variant="primary" navigate={~m"/new"}>Add an endpoint</.button>
        </:actions>
      </.header>

      <div :if={@endpoints == []} class="kunai-empty">
        <p class="kunai-empty-title">No endpoints yet</p>
        <p class="kunai-muted">
          Give a URL, choose its events, and every one of them is sent to it, signed.
        </p>
        <.button variant="primary" navigate={~m"/new"}>Add an endpoint</.button>
      </div>

      <table :if={@endpoints != []} class="kunai-table" id="kunai-endpoints">
        <thead>
          <tr>
            <th>URL</th>
            <th>Events</th>
            <th>Status</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={endpoint <- @endpoints} id={endpoint.id}>
            <td>
              <.link navigate={~m"/#{endpoint.id}"} class="kunai-link kunai-mono">{endpoint.url}</.link>
              <p :if={endpoint.description} class="kunai-muted">{endpoint.description}</p>
            </td>
            <td class="kunai-mono">{events(endpoint.events)}</td>
            <td><.status status={endpoint_status(endpoint)} /></td>
            <td><.time at={endpoint.inserted_at} /></td>
          </tr>
        </tbody>
      </table>
      <p :if={@more?} class="kunai-muted">The first 100 endpoints are shown.</p>
    </.page>
    """
  end

  defp events(["*"]), do: "All events"
  defp events([one]), do: one
  defp events([first | rest]), do: "#{first} and #{length(rest)} more"
end
