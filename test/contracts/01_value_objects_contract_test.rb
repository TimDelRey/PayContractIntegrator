require "test_helper"
require_relative "support/routing_contract_helpers"

class ValueObjectsContractTest < ActiveSupport::TestCase
  include RoutingContractHelpers

  test "domain value objects expose the frozen cross-team schema" do
    payment = operation
    candidate = provider
    routing_policy = policy
    routing_state = state(providers: [ candidate ])
    outcome = Routing::Outcome.new(status: :approved, latency_sec: 12)

    assert_equal "op-1", payment.id
    assert_equal 10_000, payment.amount
    assert_equal "provider-a", candidate.id
    assert_equal BigDecimal("90"), candidate.conversion_24h
    assert_equal "spacepayments", routing_policy.fallback_provider_id
    assert_equal 0, routing_state.providers.fetch("provider-a").selected_count
    assert_equal :approved, outcome.status
  end

  test "domain value objects use value semantics and reject unknown fields" do
    first = operation
    second = operation

    assert_equal first, second
    assert_raises(ArgumentError) { Routing::Operation.new(**first.to_h, unknown: true) }
  end

  test "batch result carries decisions final state and audit events" do
    candidate = provider
    final_state = state(providers: [ candidate ])
    attempt = Routing::Attempt.new(
      provider: candidate.id,
      decision: :selected,
      reason: :only_eligible_provider,
      details: nil
    )
    decision = Routing::Decision.new(
      operation_id: "op-1",
      selected_provider: candidate.id,
      attempts: [ attempt ],
      simulated_result: :approved,
      latency_sec: 12
    )
    result = Routing::BatchResult.new(
      decisions: [ decision ],
      final_state: final_state,
      events: []
    )

    assert_equal [ decision ], result.decisions
    assert_same final_state, result.final_state
    assert_equal [], result.events
  end
end
