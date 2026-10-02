# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "manyfold_printables"
  spec.version = "0.0.0"
  spec.authors = ["Max Dymond"]
  spec.summary = "Link Manyfold models to Printables and sync their details"
  spec.description = "Find public Printables models with fuzzy search, link them to Manyfold, and sync model and creator metadata and images."
  spec.homepage = "https://github.com/cmeister2/manyfold_printables"
  spec.metadata["manyfold_version"] = ">= 0.146.0"
  spec.files = Dir["app/**/*", "config/**/*", "db/**/*", "lib/**/*"]
  spec.require_paths = ["lib"]
end
