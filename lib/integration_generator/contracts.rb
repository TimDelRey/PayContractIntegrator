# frozen_string_literal: true

module IntegrationGenerator
  # Structured, immutable diagnostic shared by every pipeline stage. Severity
  # is either :error (blocks generation) or :warning (informational).
  Diagnostic = Data.define(:severity, :code, :message, :source_path, :hint)
end
