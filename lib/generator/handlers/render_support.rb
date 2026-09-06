module Generator
  module Handlers
    module RenderSupport
      include SymbolOrStringFetch

      def join_lines(*lines) = lines.join("\n")
      def fetch_or(hash, key, default) = hash.fetch(key) { hash.fetch(key.to_s, default) }
      def env_name(ir, suffix) = "#{ir.env_prefix}_#{suffix}"
      def money_expression(expression, transformation) = "Integer(#{expression}) * #{fetch(transformation, :multiplier)}"
    end
  end
end
