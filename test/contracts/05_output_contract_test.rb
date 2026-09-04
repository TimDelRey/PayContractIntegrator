require "test_helper"
require_relative "support/routing_contract_helpers"

class OutputContractTest < ActiveSupport::TestCase
  include RoutingContractHelpers

  test "decision serializer is a projection and preserves decision and attempt order" do
    result = batch_result_fixture

    payload = RoutingIO::DecisionSerializer.new.call(result)

    assert_instance_of Array, payload
    assert_equal %w[op-1 op-2], payload.map { |item| item.fetch("operation_id") }
    assert_equal %w[provider-a provider-b],
      payload.first.fetch("attempts").map { |item| item.fetch("provider") }
    assert_equal %w[operation_id selected_provider attempts simulated_result latency_sec],
      payload.first.keys
    assert_equal %w[provider decision reason details],
      payload.first.fetch("attempts").first.keys
    assert_equal "skipped", payload.first.fetch("attempts").first.fetch("decision")
    assert_equal "provider_rejected", payload.first.fetch("attempts").first.fetch("reason")
  end

  test "report derives totals distribution reasons and utilization from batch result" do
    providers = [ provider(id: "provider-a"), provider(id: "provider-b") ]
    result = batch_result_fixture(providers: providers)

    report = RoutingIO::ReportBuilder.new.call(
      batch_result: result,
      providers: providers,
      initial_state: state(providers: providers),
      policy: policy,
      period: Date.new(2026, 7, 30)
    )

    assert_equal "2026-07-30", report.fetch("period")
    assert_equal 2, report.fetch("total_operations")
    assert_equal 1, report.dig("distribution", "provider-b", "count")
    assert_equal 1, report.dig("skip_reasons", "provider_rejected")
    assert report.key?("projected_daily_utilization")
    assert_instance_of Array, report.fetch("recommendations")
  end

  private

  def batch_result_fixture(providers: nil)
    providers ||= [ provider(id: "provider-a"), provider(id: "provider-b") ]
    attempts = [
      Routing::Attempt.new(
        provider: "provider-a",
        decision: :skipped,
        reason: :provider_rejected,
        details: "provider returned rejected"
      ),
      Routing::Attempt.new(
        provider: "provider-b",
        decision: :selected,
        reason: :highest_combined_score,
        details: nil
      )
    ]
    decisions = [
      Routing::Decision.new(
        operation_id: "op-1",
        selected_provider: "provider-b",
        attempts: attempts,
        simulated_result: :approved,
        latency_sec: 8
      ),
      Routing::Decision.new(
        operation_id: "op-2",
        selected_provider: "provider-a",
        attempts: [
          Routing::Attempt.new(
            provider: "provider-a",
            decision: :selected,
            reason: :highest_combined_score,
            details: nil
          )
        ],
        simulated_result: :approved,
        latency_sec: 4
      )
    ]
    final_state = state(providers: providers)

    Routing::BatchResult.new(
      decisions: decisions,
      final_state: final_state,
      events: []
    )
  end
end
