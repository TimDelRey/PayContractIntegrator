# frozen_string_literal: true

# Spec Compiler (block 1) uses the same Diagnostic/CompileResult/IntegrationIR/
# OperationIR/FieldIR classes that the Artifact Generator (block 2) accepts --
# defined once in Generator::contracts, required by lib/integration_generator.rb
# before any block-1 file. No duplicate contract classes in a second namespace.
