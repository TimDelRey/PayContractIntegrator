require "test_helper"
require_relative "support/routing_contract_helpers"

class EligibilityCheckerContractTest < ActiveSupport::TestCase
  include RoutingContractHelpers

  test "an eligible provider has no violations" do
    candidate = provider

    result = checker.call(
      operation: operation,
      provider: candidate,
      provider_state: provider_state,
      state: state(providers: [ candidate ])
    )

    assert_predicate result, :eligible?
    assert_empty result.violations
  end

  test "all hard violations are returned in configured priority order" do
    candidate = provider(
      status: "disabled",
      limit_amount_max: 5_000,
      available_requisites: 0
    )

    result = checker.call(
      operation: operation(amount: 10_000),
      provider: candidate,
      provider_state: provider_state,
      state: state(providers: [ candidate ])
    )

    refute_predicate result, :eligible?
    assert_equal %i[
      provider_inactive
      amount_exceeds_limit
      no_available_requisites
    ], result.violations.map(&:reason)
    assert result.violations.all? { |violation| violation.details.is_a?(String) }
  end

  test "limits are inclusive and exceeding them by one is rejected" do
    candidate = provider(
      daily_amount_limit: 20_000,
      in_progress_count_limit: 1,
      in_progress_amount_limit: 10_000
    )

    exactly_at_limits = checker.call(
      operation: operation(amount: 10_000),
      provider: candidate,
      provider_state: provider_state(
        daily_approved_amount: 10_000,
        in_progress_count: 0,
        in_progress_amount: 0
      ),
      state: state(providers: [ candidate ])
    )
    over_daily_limit = checker.call(
      operation: operation(amount: 10_001),
      provider: candidate,
      provider_state: provider_state(daily_approved_amount: 10_000),
      state: state(providers: [ candidate ])
    )

    assert_predicate exactly_at_limits, :eligible?
    assert_includes over_daily_limit.violations.map(&:reason), :daily_amount_limit_exceeded
  end

  private

  def checker
    Routing::EligibilityChecker.new(policy: policy)
  end
end
