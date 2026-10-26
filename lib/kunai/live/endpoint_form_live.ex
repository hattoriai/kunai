defmodule Kunai.Live.EndpointFormLive do
  @moduledoc false
  # A new endpoint, or one changed. A new one shows its secret once made.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Kunai.Router

  import Kunai.Components

  alias Kunai.Endpoint

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.kunai_scope
    catalog = Kunai.Config.catalog()

    case endpoint(socket.assigns.live_action, params, scope) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "That endpoint does not exist.") |> push_navigate(to: ~m"/")}

      endpoint ->
        {:ok,
         socket
         |> assign(
           page_title: if(endpoint.id, do: "Edit endpoint", else: "Add an endpoint"),
           endpoint: endpoint,
           families: families(catalog),
           grantable: catalog.scopes(scope),
           versions: catalog.versions(),
           signing: "hmac",
           created: nil
         )
         |> assign_form(Endpoint.changeset(endpoint, %{}))}
    end
  end

  defp endpoint(:new, _params, _scope),
    do: %Endpoint{events: ["*"], api_version: Kunai.Config.catalog().latest_version()}

  defp endpoint(:edit, %{"id" => id}, scope), do: Kunai.get_endpoint(scope, id)

  # The catalog's events by family, "page" for "page.published".
  defp families(catalog) do
    catalog.event_types()
    |> Enum.reject(&(&1.name == "kunai.ping"))
    |> Enum.group_by(&(&1.name |> String.split(".") |> hd()))
    |> Enum.sort()
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :endpoint))

  @impl true
  def handle_event("validate", %{"endpoint" => params} = all, socket) do
    changeset =
      socket.assigns.endpoint
      |> Endpoint.changeset(clean(params))
      |> Map.put(:action, :validate)

    {:noreply,
     socket |> assign(signing: all["signing"] || socket.assigns.signing) |> assign_form(changeset)}
  end

  def handle_event("save", %{"endpoint" => params} = all, socket) do
    save(socket, socket.assigns.live_action, clean(params), all["signing"])
  end

  defp save(socket, :new, params, signing) do
    opts = [signing: if(signing == "ed25519", do: :ed25519, else: :hmac)]

    case Kunai.create_endpoint(socket.assigns.kunai_scope, params, opts) do
      {:ok, endpoint, secret} ->
        {:noreply, assign(socket, created: {endpoint, secret}, page_title: "Endpoint added")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params, _signing) do
    case Kunai.update_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint, params) do
      {:ok, endpoint} ->
        {:noreply,
         socket |> put_flash(:info, "Endpoint saved.") |> push_navigate(to: ~m"/#{endpoint.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Lists of checkboxes come with an empty value, so that none checked
  # is a list too.
  defp clean(params) do
    params
    |> Map.update("events", [], &Enum.reject(&1, fn value -> value == "" end))
    |> Map.update("scopes", [], &Enum.reject(&1, fn value -> value == "" end))
  end

  @impl true
  def render(%{created: {endpoint, secret}} = assigns) do
    assigns = assign(assigns, endpoint: endpoint, secret: secret)

    ~H"""
    <.page mount={@mount} flash={@flash} scope={@kunai_scope}>
      <.header title="Endpoint added" back={~m"/"}>
        <:subtitle><span class="kunai-mono">{@endpoint.url}</span></:subtitle>
      </.header>

      <.section title="Signing secret">
        <p>
          The endpoint checks each request with this {if String.starts_with?(@secret, "whpk_"),
            do: "public key",
            else: "secret"}: keep it where its code reads it.
          It can be shown again on the endpoint's page.
        </p>
        <.secret id="kunai-new-secret" value={@secret} />
        <p class="kunai-hint">
          Requests are signed as Standard Webhooks says: its libraries check them in any language.
        </p>
      </.section>

      <div class="kunai-actions">
        <.button variant="primary" navigate={~m"/#{@endpoint.id}"}>Go to the endpoint</.button>
      </div>
    </.page>
    """
  end

  def render(assigns) do
    ~H"""
    <.page mount={@mount} flash={@flash} scope={@kunai_scope}>
      <.header title={@page_title} back={~m"/"} />

      <.form for={@form} id="kunai-endpoint-form" class="kunai-form" phx-change="validate" phx-submit="save">
        <.field label="URL" for="endpoint_url" errors={errors(@form[:url])} hint="HTTPS, on an address the internet can reach.">
          <input
            id="endpoint_url"
            type="url"
            name={@form[:url].name}
            value={@form[:url].value}
            class="kunai-input"
            placeholder="https://example.com/webhooks"
            autocomplete="off"
            phx-debounce="300"
          />
        </.field>

        <.field label="Description" for="endpoint_description" errors={errors(@form[:description])}>
          <input
            id="endpoint_description"
            type="text"
            name={@form[:description].name}
            value={@form[:description].value}
            class="kunai-input"
            placeholder="What it is for, for the people who look after it"
            phx-debounce="300"
          />
        </.field>

        <fieldset class="kunai-fieldset">
          <legend class="kunai-label">Events</legend>
          <p :for={error <- errors(@form[:events])} class="kunai-error">{error}</p>
          <input type="hidden" name="endpoint[events][]" value="" />
          <label class="kunai-check">
            <input type="checkbox" name="endpoint[events][]" value="*" checked={"*" in events(@form)} />
            <span>All events, those added later too</span>
          </label>
          <div :for={{family, types} <- @families} :if={"*" not in events(@form)} class="kunai-family">
            <label class="kunai-check">
              <input
                type="checkbox"
                name="endpoint[events][]"
                value={family <> ".*"}
                checked={(family <> ".*") in events(@form)}
              />
              <span class="kunai-mono">{family}.*</span>
            </label>
            <div :if={(family <> ".*") not in events(@form)} class="kunai-checks">
              <label :for={type <- types} class="kunai-check">
                <input type="checkbox" name="endpoint[events][]" value={type.name} checked={type.name in events(@form)} />
                <span class="kunai-mono">{type.name}</span>
                <span :if={type.doc} class="kunai-muted">{type.doc}</span>
              </label>
            </div>
          </div>
        </fieldset>

        <fieldset :if={@grantable != []} class="kunai-fieldset">
          <legend class="kunai-label">Access</legend>
          <p class="kunai-hint">An event reaches the endpoint only when it has the event's access.</p>
          <p :for={error <- errors(@form[:scopes])} class="kunai-error">{error}</p>
          <input type="hidden" name="endpoint[scopes][]" value="" />
          <label :for={scope <- @grantable} class="kunai-check">
            <input type="checkbox" name="endpoint[scopes][]" value={scope} checked={scope in scopes(@form, @grantable)} />
            <span class="kunai-mono">{scope}</span>
          </label>
        </fieldset>

        <fieldset class="kunai-fieldset">
          <legend class="kunai-label">Payload</legend>
          <label class="kunai-check">
            <input type="radio" name="endpoint[payload]" value="full" checked={@form[:payload].value != "thin"} />
            <span>The whole object, as it was when it changed</span>
          </label>
          <label class="kunai-check">
            <input type="radio" name="endpoint[payload]" value="thin" checked={@form[:payload].value == "thin"} />
            <span>Its id only: the endpoint asks the API for the rest</span>
          </label>
        </fieldset>

        <fieldset class="kunai-fieldset">
          <legend class="kunai-label">Order</legend>
          <input type="hidden" name="endpoint[ordered]" value="false" />
          <label class="kunai-check">
            <input type="checkbox" name="endpoint[ordered]" value="true" checked={@form[:ordered].value in [true, "true"]} />
            <span>One at a time, in the order of the events</span>
          </label>
          <p class="kunai-hint">Off, events arrive as soon as they can, in any order; one failing holds up none of the others.</p>
        </fieldset>

        <.field :if={length(@versions) > 1} label="Version" for="endpoint_api_version" hint="The version of the payloads it receives.">
          <select id="endpoint_api_version" name="endpoint[api_version]" class="kunai-input">
            <option :for={version <- Enum.reverse(@versions)} value={version} selected={version == @form[:api_version].value}>
              {version}
            </option>
          </select>
        </.field>

        <fieldset :if={@live_action == :new} class="kunai-fieldset">
          <legend class="kunai-label">Signing</legend>
          <label class="kunai-check">
            <input type="radio" name="signing" value="hmac" checked={@signing != "ed25519"} />
            <span>A shared secret (HMAC-SHA256)</span>
          </label>
          <label class="kunai-check">
            <input type="radio" name="signing" value="ed25519" checked={@signing == "ed25519"} />
            <span>A key pair (Ed25519): the endpoint keeps only a public key</span>
          </label>
        </fieldset>

        <div class="kunai-actions">
          <.button variant="primary" type="submit" phx-disable-with="Saving…">
            {if @live_action == :new, do: "Add the endpoint", else: "Save"}
          </.button>
          <.button variant="quiet" navigate={if @endpoint.id, do: ~m"/#{@endpoint.id}", else: ~m"/"}>Cancel</.button>
        </div>
      </.form>
    </.page>
    """
  end

  defp events(form), do: List.wrap(form[:events].value)

  # A new endpoint gets every scope its maker may give, unless they choose.
  defp scopes(form, grantable) do
    case form[:scopes].value do
      [] -> if form.source.data.id, do: [], else: grantable
      nil -> grantable
      scopes -> scopes
    end
  end
end
