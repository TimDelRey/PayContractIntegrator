require "bigdecimal"

module RoutingContractHelpers
  DEFAULT_TIME = Time.utc(2026, 7, 30, 12, 0, 0)

  def operation(**overrides)
    attributes = {
      id: "op-1",
      amount: 10_000,
      bank: "alpha",
      created_at: DEFAULT_TIME
    }.merge(overrides)

    Routing::Operation.new(**attributes)
  end

  def provider(**overrides)
    attributes = {
      id: "provider-a",
      status: "active",
      limit_amount_min: 100,
      limit_amount_max: 100_000,
      daily_amount_limit: 1_000_000,
      daily_approved_amount: 0,
      in_progress_count_limit: 10,
      in_progress_count: 0,
      in_progress_amount_limit: 500_000,
      in_progress_amount: 0,
      available_requisites: 1,
      banks: [],
      exclude_banks: [],
      provider_margin_pct: BigDecimal("1.0"),
      merchant_margin_pct: BigDecimal("2.0"),
      allow_negative_agreement: false,
      traffic_percentage: BigDecimal("50"),
      volume_share_pct: BigDecimal("50"),
      conversion_24h: BigDecimal("90"),
      priority: 1,
      requests_per_minute_limit: 10,
      daily_turnover_min: nil,
      daily_turnover_max: nil
    }.merge(overrides)

    Routing::Provider.new(**attributes)
  end

  def provider_state(**overrides)
    attributes = {
      daily_approved_amount: 0,
      in_progress_count: 0,
      in_progress_amount: 0,
      selected_count: 0,
      selected_amount: 0,
      approved_count: 0,
      rejected_count: 0,
      expired_count: 0
    }.merge(overrides)

    Routing::ProviderState.new(**attributes)
  end

  def state(providers:, **overrides)
    provider_states = providers.to_h do |item|
      [ item.id, provider_state(daily_approved_amount: item.daily_approved_amount) ]
    end

    attributes = {
      providers: provider_states,
      routed_count: 0,
      routed_amount: 0,
      minute_buckets: {}
    }.merge(overrides)

    Routing::State.new(**attributes)
  end

  def policy(**overrides)
    attributes = {
      weights: {
        count_share: BigDecimal("1"),
        conversion: BigDecimal("1")
      },
      reason_priority: %i[
        provider_inactive
        amount_below_limit
        amount_exceeds_limit
        daily_amount_limit_exceeded
        in_progress_count_limit_exceeded
        in_progress_amount_limit_exceeded
        bank_not_in_list
        bank_excluded
        negative_margin_not_allowed
        no_available_requisites
        rate_limit_exceeded
        daily_turnover_max_exceeded
      ],
      fallback_provider_id: "spacepayments",
      timeout_sec: 30,
      random_seed: 20_260_730
    }.merge(overrides)

    Routing::Policy.new(**attributes)
  end

  class SequenceResolver
    attr_reader :calls

    def initialize(statuses)
      @statuses = statuses.dup
      @calls = []
    end

    def call(operation:, provider:, attempt_no:)
      @calls << {
        operation_id: operation.id,
        provider_id: provider.id,
        attempt_no: attempt_no
      }

      status = @statuses.fetch(@calls.length - 1)
      Routing::Outcome.new(status: status, latency_sec: @calls.length)
    end
  end

  def run_engine(operations:, providers:, resolver:, initial_state: nil, custom_policy: nil)
    initial_state ||= state(providers: providers)

    Routing::Engine.new(
      policy: custom_policy || policy,
      outcome_resolver: resolver
    ).call(
      operations: operations,
      providers: providers,
      initial_state: initial_state
    )
  end
end
