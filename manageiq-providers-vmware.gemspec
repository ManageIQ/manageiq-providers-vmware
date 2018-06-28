$:.push File.expand_path("../lib", __FILE__)

require "manageiq/providers/vmware/version"

Gem::Specification.new do |s|
  s.name        = "manageiq-providers-vmware"
  s.version     = ManageIQ::Providers::Vmware::VERSION
  s.authors     = ["ManageIQ Developers"]
  s.homepage    = "https://github.com/ManageIQ/manageiq-providers-vmware"
  s.summary     = "Vmware Provider for ManageIQ"
  s.description = "Vmware Provider for ManageIQ"
  s.licenses    = ["Apache-2.0"]

  s.files = Dir["{app,config,lib}/**/*"]

  s.add_dependency("fog-vcloud-director", ["~> 0.2.2"])
  s.add_dependency "fog-core",                "~>1.40"
  s.add_dependency "vmware_web_service",      "~>0.2.10"
  s.add_dependency "rbvmomi",                 "~>1.13.0"

  s.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
  s.add_development_dependency "simplecov"
end
