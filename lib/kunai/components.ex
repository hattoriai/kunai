defmodule Kunai.Components do
  @moduledoc """
  The pieces of Kunai's pages, styled by `kunai.css` (`.kunai-*` classes,
  every colour and space a `--kunai-*` property the app may set).
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  A page of Kunai's: in the app's layout component when the mount names
  one (`:app_layout`), with its flash.
  """
  attr(:mount, :map, required: true)
  attr(:flash, :map, default: %{})
  attr(:scope, :any, default: nil)
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <%= case @mount.options[:app_layout] do %>
      <% {module, fun} -> %>
        {apply(module, fun, [
          %{
            __changed__: nil,
            flash: @flash,
            current_scope: @scope,
            inner_block: [%{__slot__: :inner_block, inner_block: fn _arg, _changed -> body(assigns) end}]
          }
        ])}
      <% nil -> %>
        <.flash_group flash={@flash} />
        {body(assigns)}
    <% end %>
    """
  end

  defp body(assigns) do
    ~H"""
    <div class="kunai">{render_slot(@inner_block)}</div>
    """
  end

  @doc "The flash of a page, when the app's layout does not show it."
  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <div :if={@flash != %{}} class="kunai kunai-flashes">
      <p
        :for={{kind, message} <- @flash}
        class={"kunai-flash kunai-flash--#{kind}"}
        role={if kind == "error", do: "alert", else: "status"}
        phx-click={JS.push("lv:clear-flash", value: %{key: kind}) |> JS.hide()}
      >
        {message}
      </p>
    </div>
    """
  end

  @doc "The head of a page: its title, a line under it, and its actions."
  attr(:title, :string, required: true)
  attr(:back, :string, default: nil)
  attr(:back_label, :string, default: "Webhooks")
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class="kunai-header">
      <.link :if={@back} navigate={@back} class="kunai-back">← {@back_label}</.link>
      <div class="kunai-header-row">
        <div>
          <h1 class="kunai-title">{@title}</h1>
          <p :if={@subtitle != []} class="kunai-subtitle">{render_slot(@subtitle)}</p>
        </div>
        <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
      </div>
    </header>
    """
  end

  @doc "A section of a page, with a title."
  attr(:title, :string, required: true)
  attr(:id, :string, default: nil)
  slot(:actions)
  slot(:inner_block, required: true)

  def section(assigns) do
    ~H"""
    <section class="kunai-section" id={@id}>
      <div class="kunai-section-head">
        <h2 class="kunai-section-title">{@title}</h2>
        <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "A button, or a link styled as one with `navigate`."
  attr(:variant, :string, default: "default", values: ~w(default primary danger quiet))
  attr(:navigate, :string, default: nil)
  attr(:rest, :global, include: ~w(type disabled form name value data-confirm))
  slot(:inner_block, required: true)

  def button(%{navigate: nil} = assigns) do
    ~H"""
    <button class={"kunai-button kunai-button--#{@variant}"} {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  def button(assigns) do
    ~H"""
    <.link navigate={@navigate} class={"kunai-button kunai-button--#{@variant}"} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc "The status of an endpoint or a delivery."
  attr(:status, :string, required: true)
  attr(:label, :string, default: nil)

  def status(assigns) do
    ~H"""
    <span class={"kunai-status kunai-status--#{tone(@status)}"}>{@label || label(@status)}</span>
    """
  end

  @doc false
  # An endpoint enabled but failing is shown as failing.
  def endpoint_status(%{status: "enabled", failing_since: %DateTime{}}), do: "failing"
  def endpoint_status(endpoint), do: endpoint.status

  defp tone(status) when status in ["enabled", "succeeded"], do: "ok"
  defp tone(status) when status in ["pending", "failing"], do: "wait"
  defp tone(status) when status in ["disabled", "failed"], do: "fail"
  defp tone(_status), do: "muted"

  defp label("enabled"), do: "Enabled"
  defp label("disabled"), do: "Disabled"
  defp label("succeeded"), do: "Delivered"
  defp label("pending"), do: "Pending"
  defp label("failed"), do: "Failed"
  defp label("failing"), do: "Failing"
  defp label(other), do: other

  @doc "A time, relative to now, its full value on hover."
  attr(:at, :any, required: true)

  def time(%{at: nil} = assigns) do
    ~H"""
    <span class="kunai-muted">—</span>
    """
  end

  def time(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} title={Calendar.strftime(@at, "%Y-%m-%d %H:%M:%S UTC")}>
      {ago(@at)}
    </time>
    """
  end

  @doc false
  def ago(at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)

    cond do
      seconds < 0 -> "in #{span(-seconds)}"
      seconds < 45 -> "just now"
      true -> "#{span(seconds)} ago"
    end
  end

  defp span(s) when s < 90, do: "#{max(s, 1)}s"
  defp span(s) when s < 5_400, do: "#{div(s, 60)}m"
  defp span(s) when s < 129_600, do: "#{div(s, 3_600)}h"
  defp span(s), do: "#{div(s, 86_400)}d"

  @doc "A JSON payload, indented."
  attr(:value, :any, required: true)

  def code(assigns) do
    ~H"""
    <pre class="kunai-code"><code>{Kunai.Pretty.json(@value)}</code></pre>
    """
  end

  @doc "A secret, in a field to copy from."
  attr(:value, :string, required: true)
  attr(:id, :string, required: true)

  def secret(assigns) do
    ~H"""
    <input
      id={@id}
      class="kunai-input kunai-secret"
      type="text"
      value={@value}
      readonly
      spellcheck="false"
      autocomplete="off"
      onfocus="this.select()"
    />
    """
  end

  @doc "A field of a form: a label, the input in the slot, its hint and errors."
  attr(:label, :string, required: true)
  attr(:for, :string, default: nil)
  attr(:hint, :string, default: nil)
  attr(:errors, :list, default: [])
  slot(:inner_block, required: true)

  def field(assigns) do
    ~H"""
    <div class={["kunai-field", @errors != [] && "kunai-field--invalid"]}>
      <label class="kunai-label" for={@for}>{@label}</label>
      {render_slot(@inner_block)}
      <p :if={@hint} class="kunai-hint">{@hint}</p>
      <p :for={error <- @errors} class="kunai-error">{error}</p>
    </div>
    """
  end

  @doc "A form field's errors, as text, once it was changed or submitted."
  def errors(%Phoenix.HTML.FormField{} = field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &Kunai.Web.error_message/1),
      else: []
  end
end
