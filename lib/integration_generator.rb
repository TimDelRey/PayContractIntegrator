# frozen_string_literal: true

module IntegrationGenerator
end

# Shared frozen contract (Diagnostic, CompileResult, IntegrationIR,
# OperationIR, FieldIR) lives in Generator::contracts -- required first so
# there is exactly one definition of each, not a duplicate per namespace.
require_relative 'generator/contracts'
require_relative 'integration_generator/contracts'
require_relative 'integration_generator/errors'
require_relative 'integration_generator/spec_loader'
require_relative 'integration_generator/local_ref_resolver'
require_relative 'integration_generator/open_api_parser'
require_relative 'integration_generator/mapping_loader'
require_relative 'integration_generator/money_resolver'
require_relative 'integration_generator/platform_field_resolver'
require_relative 'integration_generator/role_resolver'
require_relative 'integration_generator/field_resolver'
require_relative 'integration_generator/auth_resolver'
require_relative 'integration_generator/webhook_resolver'
require_relative 'integration_generator/status_error_resolver'
require_relative 'integration_generator/semantic_resolver'
require_relative 'integration_generator/ir_builder'
require_relative 'integration_generator/compiler'
