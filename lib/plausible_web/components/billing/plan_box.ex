defmodule PlausibleWeb.Components.Billing.PlanBox do
  @moduledoc false

  use Phoenix.Component
  require Plausible.Billing.Subscription.Status
  alias PlausibleWeb.Components.Billing.{PlanBenefits, Notice}
  alias Plausible.Billing.{Plan, Quota, Subscription}
  alias PlausibleWeb.Router.Helpers, as: Routes

  def standard(assigns) do
    highlight =
      cond do
        assigns.owned -> "Current"
        assigns.recommended -> "Recommended"
        true -> nil
      end

    assigns = assign(assigns, :highlight, highlight)

    ~H"""
    <div
      id={"#{@kind}-plan-box"}
      class={[
        "shadow-lg bg-white rounded-3xl px-6 sm:px-8 py-4 sm:py-6 dark:bg-gray-800",
        !@highlight && "dark:ring-gray-600",
        @highlight && "ring-2 ring-indigo-600 dark:ring-indigo-300"
      ]}
    >
      <div class="flex items-center justify-between gap-x-4">
        <h3 class={[
          "text-lg font-semibold leading-8",
          !@highlight && "text-gray-900 dark:text-gray-100",
          @highlight && "text-indigo-600 dark:text-indigo-300"
        ]}>
          <%= String.capitalize(to_string(@kind)) %>
        </h3>
        <.pill :if={@highlight} text={@highlight} />
      </div>
      <div>
        <.render_price_info available={@available} {assigns} />
        <%= if @available do %>
          <.checkout id={"#{@kind}-checkout"} {assigns} />
        <% else %>
          <.contact_button class="bg-indigo-600 hover:bg-indigo-500 text-white" />
        <% end %>
      </div>
      <%= if @owned && @kind == :growth && @plan_to_render.generation < 4 do %>
        <Notice.growth_grandfathered />
      <% else %>
        <PlanBenefits.render benefits={@benefits} class="text-gray-600 dark:text-gray-100" />
      <% end %>
    </div>
    """
  end

  def enterprise(assigns) do
    ~H"""
    <div
      id="enterprise-plan-box"
      class="rounded-3xl px-6 sm:px-8 py-4 sm:py-6 bg-gray-900 shadow-xl dark:bg-gray-800 dark:ring-gray-600"
    >
      <h3 class="text-lg font-semibold leading-8 text-white dark:text-gray-100">Enterprise</h3>
      <p class="mt-6 flex items-baseline gap-x-1">
        <span class="text-4xl font-bold tracking-tight text-white dark:text-gray-100">
          Custom
        </span>
      </p>
      <p class="h-4 mt-1"></p>
      <.contact_button class="" />
      <PlanBenefits.render benefits={@benefits} class="text-gray-300 dark:text-gray-100" />
    </div>
    """
  end

  defp pill(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-x-4">
      <p
        id="highlight-pill"
        class="rounded-full bg-indigo-600/10 px-2.5 py-1 text-xs font-semibold leading-5 text-indigo-600 dark:text-indigo-300 dark:ring-1 dark:ring-indigo-300/50"
      >
        <%= @text %>
      </p>
    </div>
    """
  end

  defp render_price_info(%{available: false} = assigns) do
    ~H"""
    <p id={"#{@kind}-custom-price"} class="mt-6 flex items-baseline gap-x-1">
      <span class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">
        Custom
      </span>
    </p>
    <p class="h-4 mt-1"></p>
    """
  end

  defp render_price_info(assigns) do
    ~H"""
    <p class="mt-6 flex items-baseline gap-x-1">
      <.price_tag
        kind={@kind}
        selected_interval={@selected_interval}
        plan_to_render={@plan_to_render}
      />
    </p>
    <p class="mt-1 text-xs">+ VAT if applicable</p>
    """
  end

  defp price_tag(%{plan_to_render: %Plan{monthly_cost: nil}} = assigns) do
    ~H"""
    <span class="text-4xl font-bold tracking-tight text-gray-900 dark:text-gray-100">
      N/A
    </span>
    """
  end

  defp price_tag(%{selected_interval: :monthly} = assigns) do
    ~H"""
    <span
      id={"#{@kind}-price-tag-amount"}
      class="text-4xl font-bold tracking-tight text-gray-900 dark:text-gray-100"
    >
      <%= @plan_to_render.monthly_cost |> Plausible.Billing.format_price() %>
    </span>
    <span
      id={"#{@kind}-price-tag-interval"}
      class="text-sm font-semibold leading-6 text-gray-600 dark:text-gray-500"
    >
      /month
    </span>
    """
  end

  defp price_tag(%{selected_interval: :yearly} = assigns) do
    ~H"""
    <span class="text-2xl font-bold w-max tracking-tight line-through text-gray-500 dark:text-gray-600 mr-1">
      <%= @plan_to_render.monthly_cost |> Money.mult!(12) |> Plausible.Billing.format_price() %>
    </span>
    <span
      id={"#{@kind}-price-tag-amount"}
      class="text-4xl font-bold tracking-tight text-gray-900 dark:text-gray-100"
    >
      <%= @plan_to_render.yearly_cost |> Plausible.Billing.format_price() %>
    </span>
    <span id={"#{@kind}-price-tag-interval"} class="text-sm font-semibold leading-6 text-gray-600">
      /year
    </span>
    """
  end

  defp checkout(assigns) do
    paddle_product_id = get_paddle_product_id(assigns.plan_to_render, assigns.selected_interval)
    change_plan_link_text = change_plan_link_text(assigns)

    subscription = assigns.user.subscription

    billing_details_expired =
      Subscription.Status.in?(subscription, [
        Subscription.Status.paused(),
        Subscription.Status.past_due()
      ])

    subscription_deleted = Subscription.Status.deleted?(subscription)
    usage_check = check_usage_within_plan_limits(assigns)

    {checkout_disabled, disabled_message} =
      cond do
        not assigns.eligible_for_upgrade? ->
          {true, nil}

        change_plan_link_text == "Currently on this plan" && not subscription_deleted ->
          {true, nil}

        usage_check != :ok ->
          {true, "Your usage exceeds this plan"}

        billing_details_expired ->
          {true, "Please update your billing details first"}

        true ->
          {false, nil}
      end

    exceeded_plan_limits =
      case usage_check do
        {:error, {:over_plan_limits, limits}} ->
          limits

        _ ->
          []
      end

    features_to_lose = assigns.usage.features -- assigns.plan_to_render.features

    assigns =
      assigns
      |> assign(:paddle_product_id, paddle_product_id)
      |> assign(:change_plan_link_text, change_plan_link_text)
      |> assign(:checkout_disabled, checkout_disabled)
      |> assign(:disabled_message, disabled_message)
      |> assign(:exceeded_plan_limits, exceeded_plan_limits)
      |> assign(:confirm_message, losing_features_message(features_to_lose))

    ~H"""
    <%= if @owned_plan && Plausible.Billing.Subscriptions.resumable?(@user.subscription) do %>
      <.change_plan_link {assigns} />
    <% else %>
      <PlausibleWeb.Components.Billing.paddle_button {assigns}>
        Upgrade
      </PlausibleWeb.Components.Billing.paddle_button>
    <% end %>
    <p
      :if={@disabled_message}
      class="h-0 text-center text-sm text-red-700 dark:text-red-500 disabled-message"
    >
      <%= if @exceeded_plan_limits != [] do %>
        <PlausibleWeb.Components.Generic.tooltip class="text-sm text-red-700 dark:text-red-500 mt-1 justify-center">
          <%= @disabled_message %>
          <:tooltip_content>
            Your usage exceeds the following limit(s):<br /><br />
            <p :for={limit <- @exceeded_plan_limits}>
              <%= Phoenix.Naming.humanize(limit) %><br />
            </p>
          </:tooltip_content>
        </PlausibleWeb.Components.Generic.tooltip>
      <% else %>
        <%= @disabled_message %>
      <% end %>
    </p>
    """
  end

  defp check_usage_within_plan_limits(%{available: false}) do
    {:error, :plan_unavailable}
  end

  defp check_usage_within_plan_limits(%{
         available: true,
         usage: usage,
         user: user,
         plan_to_render: plan
       }) do
    # At this point, the user is *not guaranteed* to have a `trial_expiry_date`,
    # because in the past we've let users upgrade without that constraint, as
    # well as transfer sites to those accounts. to these accounts we won't be
    # offering an extra pageview limit allowance margin though.
    invited_user? = is_nil(user.trial_expiry_date)

    trial_active_or_ended_recently? =
      not invited_user? && Date.diff(Date.utc_today(), user.trial_expiry_date) <= 10

    limit_checking_opts =
      cond do
        user.allow_next_upgrade_override ->
          [ignore_pageview_limit: true]

        trial_active_or_ended_recently? && plan.volume == "10k" ->
          [pageview_allowance_margin: 0.3]

        trial_active_or_ended_recently? ->
          [pageview_allowance_margin: 0.15]

        true ->
          []
      end

    Quota.ensure_within_plan_limits(usage, plan, limit_checking_opts)
  end

  defp get_paddle_product_id(%Plan{monthly_product_id: plan_id}, :monthly), do: plan_id
  defp get_paddle_product_id(%Plan{yearly_product_id: plan_id}, :yearly), do: plan_id

  defp change_plan_link_text(
         %{
           owned_plan: %Plan{kind: from_kind, monthly_pageview_limit: from_volume},
           plan_to_render: %Plan{kind: to_kind, monthly_pageview_limit: to_volume},
           current_interval: from_interval,
           selected_interval: to_interval
         } = _assigns
       ) do
    cond do
      from_kind == :business && to_kind == :growth ->
        "Downgrade to Growth"

      from_kind == :growth && to_kind == :business ->
        "Upgrade to Business"

      from_volume == to_volume && from_interval == to_interval ->
        "Currently on this plan"

      from_volume == to_volume ->
        "Change billing interval"

      from_volume > to_volume ->
        "Downgrade"

      true ->
        "Upgrade"
    end
  end

  defp change_plan_link_text(_), do: nil

  defp change_plan_link(assigns) do
    confirmed =
      if assigns.confirm_message, do: "confirm(\"#{assigns.confirm_message}\")", else: "true"

    assigns = assign(assigns, :confirmed, confirmed)

    ~H"""
    <button
      id={"#{@kind}-checkout"}
      onclick={"if (#{@confirmed}) {window.location = '#{Routes.billing_path(PlausibleWeb.Endpoint, :change_plan_preview, @paddle_product_id)}'}"}
      class={[
        "w-full mt-6 block rounded-md py-2 px-3 text-center text-sm font-semibold leading-6 text-white",
        !@checkout_disabled && "bg-indigo-600 hover:bg-indigo-500",
        @checkout_disabled && "pointer-events-none bg-gray-400 dark:bg-gray-600"
      ]}
    >
      <%= @change_plan_link_text %>
    </button>
    """
  end

  defp losing_features_message([]), do: nil

  defp losing_features_message(features_to_lose) do
    features_list_str =
      features_to_lose
      |> Enum.map(& &1.display_name)
      |> PlausibleWeb.TextHelpers.pretty_join()

    "This plan does not support #{features_list_str}, which you are currently using. Please note that by subscribing to this plan you will lose access to #{if length(features_to_lose) == 1, do: "this feature", else: "these features"}."
  end

  defp contact_button(assigns) do
    ~H"""
    <.link
      href="https://plausible.io/contact"
      class={[
        "mt-6 block rounded-md py-2 px-3 text-center text-sm font-semibold leading-6 bg-gray-800 hover:bg-gray-700 text-white dark:bg-indigo-600 dark:hover:bg-indigo-500",
        @class
      ]}
    >
      Contact us
    </.link>
    """
  end
end
