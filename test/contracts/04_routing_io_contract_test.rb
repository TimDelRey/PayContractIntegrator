require "test_helper"
require_relative "support/routing_contract_helpers"

class RoutingIoContractTest < ActiveSupport::TestCase
  include RoutingContractHelpers

  test "normalizer converts external keys and decimal percentages without Float" do
    raw_operation = {
      "id" => "op-7",
      "amount" => 15_000,
      "bank" => "ALPHA",
      "created_at" => "2026-07-30T12:00:00Z"
    }
    raw_provider = raw_provider_hash

    normalized_operation = RoutingIO::Normalizer.operation(raw_operation)
    normalized_provider = RoutingIO::Normalizer.provider(raw_provider)

    assert_instance_of Routing::Operation, normalized_operation
    assert_equal "alpha", normalized_operation.bank
    assert_equal Time.utc(2026, 7, 30, 12), normalized_operation.created_at
    assert_instance_of BigDecimal, normalized_provider.conversion_24h
    assert_equal BigDecimal("91.5"), normalized_provider.conversion_24h
  end

  test "normalizer rejects fractional and negative monetary values" do
    fractional = raw_provider_hash.merge("daily_amount_limit" => 10_000.5)
    negative = raw_provider_hash.merge("daily_amount_limit" => -1)

    assert_raises(Routing::InputError) { RoutingIO::Normalizer.provider(fractional) }
    assert_raises(Routing::InputError) { RoutingIO::Normalizer.provider(negative) }
  end

  test "outcome simulator is deterministic and does not use global random state" do
    simulator = RoutingIO::OutcomeSimulator.new(seed: 1234)
    candidate = provider(conversion_24h: BigDecimal("75"))

    first = simulator.call(operation: operation, provider: candidate, attempt_no: 1)
    srand(999)
    second = simulator.call(operation: operation, provider: candidate, attempt_no: 1)

    assert_equal first, second
    assert_includes %i[approved rejected expired], first.status
    assert_operator first.latency_sec, :>=, 0
  end

  private

  def raw_provider_hash
    {
      "id" => "provider-a",
      "status" => "active",
      "limit_amount_min" => 100,
      "limit_amount_max" => 100_000,
      "daily_amount_limit" => 1_000_000,
      "daily_approved_amount" => 0,
      "in_progress_count_limit" => 10,
      "in_progress_count" => 0,
      "in_progress_amount_limit" => 500_000,
      "in_progress_amount" => 0,
      "available_requisites" => 1,
      "banks" => [ "ALPHA" ],
      "exclude_banks" => [],
      "provider_margin_pct" => "1.0",
      "merchant_margin_pct" => "2.0",
      "allow_negative_agreement" => false,
      "traffic_percentage" => "50",
      "volume_share_pct" => "50",
      "conversion_24h" => "91.5",
      "priority" => 1,
      "requests_per_minute_limit" => 10,
      "daily_turnover_min" => nil,
      "daily_turnover_max" => nil
    }
  end
end
