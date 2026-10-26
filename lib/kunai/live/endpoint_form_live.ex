defmodule Kunai.Live.EndpointFormLive do
  @moduledoc false
  # A new endpoint, or one changed. A new one shows its secret once made.

  use Kunai.Live.Page

  alias Kunai.Endpoint

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.kunai_scope
    catalog = Kunai.catalog()

    case endpoint(socket.assigns.live_action, params, scope) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, t("That endpoint does not exist."))
         |> push_navigate(to: socket.assigns.kunai.base)}

      endpoint ->
        {:ok,
         socket
         |> assign(
           page_title: if(endpoint.id, do: t("Edit endpoint"), else: t("Add endpoint")),
           endpoint: endpoint,
           families: families(catalog),
           grantable: catalog.scopes(scope),
           versions: catalog.versions(),
           signing: "hmac",
           query: "",
           created: nil
         )
         |> assign_form(Endpoint.changeset(endpoint, %{}))}
    end
  end

  # A new one, its URL given by a link (the inbox's) when it has one.
  defp endpoint(:new, params, _scope),
    do: %Endpoint{
      events: ["*"],
      api_version: Kunai.catalog().latest_version(),
      url: params["url"]
    }

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
     socket
     |> assign(signing: all["signing"] || socket.assigns.signing, query: all["q"] || "")
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"endpoint" => params} = all, socket) do
    save(socket, socket.assigns.live_action, clean(params), all["signing"])
  end

  defp save(socket, :new, params, signing) do
    opts = [signing: if(signing == "ed25519", do: :ed25519, else: :hmac)]

    case Kunai.create_endpoint(socket.assigns.kunai_scope, params, opts) do
      {:ok, endpoint, secret} ->
        {:noreply, assign(socket, created: {endpoint, secret}, page_title: t("Endpoint added"))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params, _signing) do
    case Kunai.update_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint, params) do
      {:ok, endpoint} ->
        {:noreply,
         socket
         |> put_flash(:info, t("Endpoint saved."))
         |> push_navigate(to: endpoint_path(socket.assigns.kunai.base, endpoint))}

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
    <.page kunai={@kunai} flash={@flash} class="kunai-narrow">
      <.header eyebrow={@kunai.eyebrow} title={t("Endpoint added")} back={@kunai.base}>
        <:subtitle><span class="kunai-mono">{@endpoint.url}</span></:subtitle>
      </.header>

      <.card title={t("Signing secret")}>
        <:description>
          {if String.starts_with?(@secret, "whpk_"),
            do: t("The endpoint verifies each request with this public key. Keep it where its code reads it."),
            else: t("The endpoint verifies each request with this secret. Keep it where its code reads it, as you would a password.")}
        </:description>
        <.secret id="kunai-new-secret" value={@secret} />
      </.card>

      <.card title={t("Verify the requests")}>
        <.verify_snippet id="kunai-new-verify" ed25519={String.starts_with?(@secret, "whpk_")} />
      </.card>

      <div class="kunai-form-actions">
        <.button variant="primary" icon="chevron-right" navigate={endpoint_path(@kunai.base, @endpoint)}>
          {t("Go to the endpoint")}
        </.button>
      </div>
    </.page>
    """
  end

  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash} class="kunai-narrow">
      <.header
        eyebrow={@kunai.eyebrow}
        title={@page_title}
        back={if @endpoint.id, do: endpoint_path(@kunai.base, @endpoint), else: @kunai.base}
        back_label={if @endpoint.id, do: t("Endpoint"), else: t("Webhooks")}
      >
        <:subtitle :if={!@endpoint.id}>{t("Choose where to send events, and which.")}</:subtitle>
      </.header>

      <.endpoint_form
        form={@form}
        families={@families}
        grantable={@grantable}
        versions={@versions}
        signing={@signing}
        query={@query}
        new?={is_nil(@endpoint.id)}
        cancel={if @endpoint.id, do: endpoint_path(@kunai.base, @endpoint), else: @kunai.base}
      />
    </.page>
    """
  end
end
