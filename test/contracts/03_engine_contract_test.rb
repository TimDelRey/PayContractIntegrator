require "test_helper"
require_relative "support/routing_contract_helpers"

class EngineContractTest < ActiveSupport::TestCase
  include RoutingContractHelpers

  test "preserves operation order and does not mutate inputs" do
    providers = [ provider ]
    operations = [ operation(id: "op-1"), operation(id: "op-2") ]
    initial_state = state(providers: providers)
    providers_snapshot = Marshal.dump(providers)
    operations_snapshot = Marshal.dump(operations)
    state_snapshot = Marshal.dump(initial_state)
    resolver = SequenceResolver.new(%i[approved approved])

    result = run_engine(
      operations: operations,
      providers: providers,
      resolver: resolver,
      initial_state: initial_state
    )

    assert_equal %w[op-1 op-2], result.decisions.map(&:operation_id)
    assert_equal providers_snapshot, Marshal.dump(providers)
    assert_equal operations_snapshot, Marshal.dump(operations)
    assert_equal state_snapshot, Marshal.dump(initial_state)
  end

  test "hard-ineligible provider is skipped before resolver is called" do
    inactive = provider(id: "inactive", status: "disabled", priority: 1)
    active = provider(id: "active", priority: 2)
    resolver = SequenceResolver.new([ :approved ])

    result = run_engine(
      operations: [ operation ],
      providers: [ inactive, active ],
      resolver: resolver
    )
    decision = result.decisions.fetch(0)

    assert_equal [ "active" ], resolver.calls.map { |call| call.fetch(:provider_id) }
    assert_equal "active", decision.selected_provider
    assert_equal :provider_inactive, decision.attempts.fetch(0).reason
    assert_equal :skipped, decision.attempts.fetch(0).decision
  end

  test "rejection cascades to the next unique provider" do
    first = provider(id: "first", priority: 1, conversion_24h: BigDecimal("99"))
    second = provider(id: "second", priority: 2, conversion_24h: BigDecimal("80"))
    resolver = SequenceResolver.new(%i[rejected approved])

    result = run_engine(
      operations: [ operation ],
      providers: [ first, second ],
      resolver: resolver,
      custom_policy: policy(weights: { cascade_priority: BigDecimal("1") })
    )
    decision = result.decisions.fetch(0)

    assert_equal %w[first second], resolver.calls.map { |call| call.fetch(:provider_id) }
    assert_equal [ 1, 2 ], resolver.calls.map { |call| call.fetch(:attempt_no) }
    assert_equal "second", decision.selected_provider
    assert_equal :provider_rejected, decision.attempts.find { |item| item.provider == "first" }.reason
    assert_equal :selected, decision.attempts.find { |item| item.provider == "second" }.decision
    assert_equal :approved, decision.simulated_result
  end

  test "an exhausted external pool invokes fallback exactly once" do
    external = provider(id: "external", priority: 1)
    fallback = provider(id: "spacepayments", priority: 99)
    resolver = SequenceResolver.new(%i[expired approved])

    result = run_engine(
      operations: [ operation ],
      providers: [ external, fallback ],
      resolver: resolver,
      custom_policy: policy(weights: { cascade_priority: BigDecimal("1") })
    )
    decision = result.decisions.fetch(0)

    assert_equal %w[external spacepayments], resolver.calls.map { |call| call.fetch(:provider_id) }
    assert_equal "spacepayments", decision.selected_provider
    assert_equal :fallback_provider, decision.attempts.last.reason
  end

  test "approved state from one operation affects the next operation" do
    limited = provider(
      id: "limited",
      daily_amount_limit: 10_000,
      priority: 1
    )
    fallback = provider(id: "spacepayments", priority: 99)
    resolver = SequenceResolver.new(%i[approved approved])

    result = run_engine(
      operations: [ operation(id: "op-1"), operation(id: "op-2") ],
      providers: [ limited, fallback ],
      resolver: resolver,
      custom_policy: policy(weights: { cascade_priority: BigDecimal("1") })
    )

    assert_equal %w[limited spacepayments], result.decisions.map(&:selected_provider)
    limited_state = result.final_state.providers.fetch("limited")
    assert_equal 1, limited_state.selected_count
    assert_equal 1, limited_state.approved_count
    assert_equal 10_000, limited_state.daily_approved_amount
    assert_equal :daily_amount_limit_exceeded,
      result.decisions.last.attempts.find { |item| item.provider == "limited" }.reason
  end

  test "technical resolver errors are not converted to payment rejection" do
    resolver = Object.new
    resolver.define_singleton_method(:call) do |**|
      raise IOError, "simulator failed"
    end

    error = assert_raises(IOError) do
      run_engine(operations: [ operation ], providers: [ provider ], resolver: resolver)
    end

    assert_equal "simulator failed", error.message
  end
end
