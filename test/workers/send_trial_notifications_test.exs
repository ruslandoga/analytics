defmodule Plausible.Workers.SendTrialNotificationsTest do
  use Plausible.DataCase
  use Bamboo.Test
  use Oban.Testing, repo: Plausible.Repo
  alias Plausible.Workers.SendTrialNotifications

  test "does not send a notification if user didn't create a site" do
    today = Date.utc_today()
    insert(:user, trial_expiry_date: Date.shift(today, day: 7))
    insert(:user, trial_expiry_date: Date.shift(today, day: 1))
    insert(:user, trial_expiry_date: today)
    insert(:user, trial_expiry_date: Date.shift(today, day: -1))

    perform_job(SendTrialNotifications, %{})

    assert_no_emails_delivered()
  end

  test "does not send a notification if user does not have a trial" do
    user = insert(:user, trial_expiry_date: nil)
    insert(:site, members: [user])

    perform_job(SendTrialNotifications, %{})

    assert_no_emails_delivered()
  end

  test "does not send a notification if user created a site but there are no pageviews" do
    user = insert(:user, trial_expiry_date: Date.utc_today() |> Date.shift(day: 7))
    insert(:site, members: [user])

    perform_job(SendTrialNotifications, %{})

    assert_no_emails_delivered()
  end

  test "does not send a notification if user is a collaborator on sites but not an owner" do
    user = insert(:user, trial_expiry_date: Date.utc_today())

    site =
      insert(:site,
        memberships: [
          build(:site_membership, user: user, role: :admin)
        ]
      )

    populate_stats(site, [build(:pageview)])

    perform_job(SendTrialNotifications, %{})

    assert_no_emails_delivered()
  end

  describe "with site and pageviews" do
    test "sends a reminder 7 days before trial ends (16 days after user signed up)" do
      user = insert(:user, trial_expiry_date: Date.utc_today() |> Date.shift(day: 7))
      site = insert(:site, members: [user])
      populate_stats(site, [build(:pageview)])

      perform_job(SendTrialNotifications, %{})

      assert_delivered_email(PlausibleWeb.Email.trial_one_week_reminder(user))
    end

    test "sends an upgrade email the day before the trial ends" do
      user = insert(:user, trial_expiry_date: Date._utc_today() |> Date.shift(day: 1))
      site = insert(:site, members: [user])
      usage = %{total: 3, custom_events: 0}

      populate_stats(site, [
        build(:pageview),
        build(:pageview),
        build(:pageview)
      ])

      perform_job(SendTrialNotifications, %{})

      assert_delivered_email(PlausibleWeb.Email.trial_upgrade_email(user, "tomorrow", usage))
    end

    test "sends an upgrade email the day the trial ends" do
      user = insert(:user, trial_expiry_date: Date.utc_today())
      site = insert(:site, members: [user])
      usage = %{total: 3, custom_events: 0}

      populate_stats(site, [
        build(:pageview),
        build(:pageview),
        build(:pageview)
      ])

      perform_job(SendTrialNotifications, %{})

      assert_delivered_email(PlausibleWeb.Email.trial_upgrade_email(user, "today", usage))
    end

    test "does not include custom event note if user has not used custom events" do
      user = insert(:user, trial_expiry_date: Date.utc_today())
      usage = %{total: 9_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)

      assert email.html_body =~
               "In the last month, your account has used 9,000 billable pageviews."
    end

    test "includes custom event note if user has used custom events" do
      user = insert(:user, trial_expiry_date: Date.utc_today())
      usage = %{total: 9_100, custom_events: 100}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)

      assert email.html_body =~
               "In the last month, your account has used 9,100 billable pageviews and custom events in total."
    end

    test "sends a trial over email the day after the trial ends" do
      user = insert(:user, trial_expiry_date: Date.utc_today() |> Date.shift(day: -1))
      site = insert(:site, members: [user])

      populate_stats(site, [
        build(:pageview),
        build(:pageview),
        build(:pageview)
      ])

      perform_job(SendTrialNotifications, %{})

      assert_delivered_email(PlausibleWeb.Email.trial_over_email(user))
    end

    test "does not send a notification if user has a subscription" do
      user = insert(:user, trial_expiry_date: Date.utc_today() |> Date.shift(day: 7))
      site = insert(:site, members: [user])

      populate_stats(site, [
        build(:pageview),
        build(:pageview),
        build(:pageview)
      ])

      insert(:subscription, user: user)

      perform_job(SendTrialNotifications, %{})

      assert_no_emails_delivered()
    end
  end

  describe "Suggested plans" do
    test "suggests 10k/mo plan" do
      user = insert(:user)
      usage = %{total: 9_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 10k/mo plan."
    end

    test "suggests 100k/mo plan" do
      user = insert(:user)
      usage = %{total: 90_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 100k/mo plan."
    end

    test "suggests 200k/mo plan" do
      user = insert(:user)
      usage = %{total: 180_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 200k/mo plan."
    end

    test "suggests 500k/mo plan" do
      user = insert(:user)
      usage = %{total: 450_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 500k/mo plan."
    end

    test "suggests 1m/mo plan" do
      user = insert(:user)
      usage = %{total: 900_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 1M/mo plan."
    end

    test "suggests 2m/mo plan" do
      user = insert(:user)
      usage = %{total: 1_800_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 2M/mo plan."
    end

    test "suggests 5m/mo plan" do
      user = insert(:user)
      usage = %{total: 4_500_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 5M/mo plan."
    end

    test "suggests 10m/mo plan" do
      user = insert(:user)
      usage = %{total: 9_000_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "we recommend you select a 10M/mo plan."
    end

    test "does not suggest a plan above that" do
      user = insert(:user)
      usage = %{total: 20_000_000, custom_events: 0}

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "please reply back to this email to get a quote for your volume"
    end

    test "does not suggest a plan when user is switching to an enterprise plan" do
      user = insert(:user)
      usage = %{total: 10_000, custom_events: 0}

      insert(:enterprise_plan, user: user, paddle_plan_id: "enterprise-plan-id")

      email = PlausibleWeb.Email.trial_upgrade_email(user, "today", usage)
      assert email.html_body =~ "please reply back to this email to get a quote for your volume"
    end
  end
end
