# frozen_string_literal: true

require_relative "lib/sure/version"

Gem::Specification.new do |spec|
  spec.name = "sure"
  spec.version = Sure::VERSION
  spec.authors = [ "Sure Contributors" ]
  spec.summary = "Command-line interface for a Sure personal finance server"
  spec.description = <<~DESC
    A first-party command-line client for Sure. It talks to the existing
    /api/v1 HTTP API, so authentication, family tenancy, authorization, and
    financial semantics stay on the server. The CLI does not load Rails.
  DESC
  spec.homepage = "https://github.com/we-promise/sure"
  spec.license = "AGPL-3.0-only"
  spec.required_ruby_version = ">= 3.4"

  # Explicit allowlist: never ship tests, fixtures, local config, or secrets.
  spec.files = Dir[
    "exe/*",
    "lib/**/*.rb",
    "config/operations.yml",
    "README.md",
    "LICENSE"
  ].select { |path| File.file?(path) }

  spec.bindir = "exe"
  spec.executables = [ "sure" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "csv", "~> 3.3.5"
  spec.add_dependency "faraday", "~> 2.14.3"
  spec.add_dependency "faraday-retry", "~> 2.3.2"
  spec.add_dependency "terminal-table", "~> 4.0.0"
  spec.add_dependency "thor", "~> 1.5.0"

  spec.add_development_dependency "minitest", "~> 5.27.0"
  spec.add_development_dependency "rake", "~> 13.4.2"
  spec.add_development_dependency "rubocop", "~> 1.76.1"
  spec.add_development_dependency "rubocop-rails-omakase", "~> 1.1.0"
  spec.add_development_dependency "webmock", "~> 3.25.1"

  spec.metadata["rubygems_mfa_required"] = "true"
end
