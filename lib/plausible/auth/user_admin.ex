defmodule Plausible.Auth.UserAdmin do
  use Plausible.Repo
  use Plausible
  require Plausible.Billing.Subscription.Status
  alias Plausible.Billing.Subscription

  def custom_index_query(_conn, _schema, query) do
    subscripton_q = from(s in Plausible.Billing.Subscription, order_by: [desc: s.inserted_at])
    from(r in query, preload: [subscription: ^subscripton_q])
  end

  def form_fields(_) do
    [
      name: nil,
      email: nil,
      previous_email: nil,
      trial_expiry_date: %{
        help_text: "Change will also update Accept Traffic Until date"
      },
      allow_next_upgrade_override: nil,
      accept_traffic_until: %{
        help_text: "Change will take up to 15 minutes to propagate"
      }
    ]
  end

  def delete(_conn, %{data: user}) do
    Plausible.Auth.delete_user(user)
  end

  def index(_) do
    [
      name: nil,
      email: nil,
      inserted_at: %{name: "Created at", value: &format_date(&1.inserted_at)},
      trial_expiry_date: %{name: "Trial expiry", value: &format_date(&1.trial_expiry_date)},
      subscription_plan: %{value: &subscription_plan/1},
      subscription_status: %{value: &subscription_status/1},
      usage: %{value: &usage_link/1},
      grace_period: %{value: &grace_period_status/1},
      accept_traffic_until: %{
        name: "Accept traffic until",
        value: &format_date(&1.accept_traffic_until)
      }
    ]
  end

  def resource_actions(_) do
    [
      unlock: %{
        name: "Unlock",
        action: fn _, user -> unlock(user) end
      },
      lock: %{
        name: "Lock",
        action: fn _, user -> lock(user) end
      },
      reset_2fa: %{
        name: "Reset 2FA",
        action: fn _, user -> disable_2fa(user) end
      }
    ]
  end

  defp lock(user) do
    if user.grace_period do
      Plausible.Billing.SiteLocker.set_lock_status_for(user, true)
      user |> Plausible.Auth.GracePeriod.end_changeset() |> Repo.update()
    else
      {:error, user, "No active grace period on this user"}
    end
  end

  defp unlock(user) do
    if user.grace_period do
      Plausible.Auth.GracePeriod.remove_changeset(user) |> Repo.update()
      Plausible.Billing.SiteLocker.set_lock_status_for(user, false)
      {:ok, user}
    else
      {:error, user, "No active grace period on this user"}
    end
  end

  def disable_2fa(user) do
    Plausible.Auth.TOTP.force_disable(user)
  end

  defp grace_period_status(%{grace_period: grace_period}) do
    case grace_period do
      nil ->
        "--"

      %{manual_lock: true, is_over: true} ->
        "Manually locked"

      %{manual_lock: true, is_over: false} ->
        "Waiting for manual lock"

      %{is_over: true} ->
        "ended"

      %{end_date: %Date{} = end_date} ->
        days_left = Date.diff(end_date, Date.utc_today())
        "#{days_left} days left"
    end
  end

  defp subscription_plan(user) do
    if Subscription.Status.active?(user.subscription) && user.subscription.paddle_subscription_id do
      quota = PlausibleWeb.AuthView.subscription_quota(user.subscription)
      interval = PlausibleWeb.AuthView.subscription_interval(user.subscription)

      manage_url =
        Plausible.Billing.PaddleApi.vendors_domain() <>
          "/subscriptions/customers/manage/" <>
          user.subscription.paddle_subscription_id

      {:safe, ~s(<a href="#{manage_url}">#{quota} \(#{interval}\)</a>)}
    else
      "--"
    end
  end

  defp subscription_status(user) do
    cond do
      user.subscription ->
        PlausibleWeb.AuthView.present_subscription_status(user.subscription.status)

      Plausible.Users.on_trial?(user) ->
        "On trial"

      true ->
        "Trial expired"
    end
  end

  on_ee do
    defp usage_link(user) do
      path = PlausibleWeb.Router.Helpers.admin_path(PlausibleWeb.Endpoint, :usage, user.id)
      {:safe, ~s(<a href="#{path}">Usage</a>)}
    end
  else
    defp usage_link(_), do: nil
  end

  defp format_date(nil), do: "--"

  defp format_date(date) do
    Calendar.strftime(date, "%Y%m%d")
  end
end
