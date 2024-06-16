defmodule Plausible.Users do
  @moduledoc """
  User context
  """
  use Plausible
  @accept_traffic_until_free ~D[2135-01-01]

  import Ecto.Query

  alias Plausible.Auth
  alias Plausible.Billing.Subscription
  alias Plausible.Repo

  @spec on_trial?(Auth.User.t()) :: boolean()
  on_ee do
    def on_trial?(%Auth.User{trial_expiry_date: nil}), do: false

    def on_trial?(user) do
      user = with_subscription(user)
      not Plausible.Billing.Subscriptions.active?(user.subscription) && trial_days_left(user) >= 0
    end
  else
    def on_trial?(_), do: true
  end

  @spec trial_days_left(Auth.User.t()) :: integer()
  def trial_days_left(user) do
    Date.diff(user.trial_expiry_date, Date.utc_today())
  end

  @spec update_accept_traffic_until(Auth.User.t()) :: Auth.User.t()
  def update_accept_traffic_until(user) do
    user
    |> Auth.User.changeset(%{accept_traffic_until: accept_traffic_until(user)})
    |> Repo.update!()
  end

  @spec accept_traffic_until(Auth.User.t()) :: Date.t()
  on_ee do
    def accept_traffic_until(user) do
      user = with_subscription(user)

      cond do
        Plausible.Users.on_trial?(user) ->
          Date.shift(user.trial_expiry_date,
            day: Auth.User.trial_accept_traffic_until_offset_days()
          )

        user.subscription && user.subscription.paddle_plan_id == "free_10k" ->
          @accept_traffic_until_free

        user.subscription && user.subscription.next_bill_date ->
          Date.shift(user.subscription.next_bill_date,
            day: Auth.User.subscription_accept_traffic_until_offset_days()
          )

        true ->
          raise "This user is neither on trial or has a valid subscription. Manual intervention required."
      end
    end
  else
    def accept_traffic_until(_user) do
      @accept_traffic_until_free
    end
  end

  def with_subscription(%Auth.User{id: user_id} = user) do
    Repo.preload(user, subscription: last_subscription_query(user_id))
  end

  def with_subscription(user_id) when is_integer(user_id) do
    Repo.one(
      from(user in Auth.User,
        left_join: last_subscription in subquery(last_subscription_query(user_id)),
        on: last_subscription.user_id == user.id,
        left_join: subscription in Subscription,
        on: subscription.id == last_subscription.id,
        where: user.id == ^user_id,
        preload: [subscription: subscription]
      )
    )
  end

  @spec has_email_code?(Auth.User.t()) :: boolean()
  def has_email_code?(user) do
    Auth.EmailVerification.any?(user)
  end

  def allow_next_upgrade_override(%Auth.User{} = user) do
    user
    |> Auth.User.changeset(%{allow_next_upgrade_override: true})
    |> Repo.update!()
  end

  def maybe_reset_next_upgrade_override(%Auth.User{} = user) do
    if user.allow_next_upgrade_override do
      user
      |> Auth.User.changeset(%{allow_next_upgrade_override: false})
      |> Repo.update!()
    else
      user
    end
  end

  defp last_subscription_query(user_id) do
    from(subscription in Subscription,
      where: subscription.user_id == ^user_id,
      order_by: [desc: subscription.inserted_at],
      limit: 1
    )
  end
end
