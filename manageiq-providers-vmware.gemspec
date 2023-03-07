# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'manageiq/providers/vmware/version'

Gem::Specification.new do |spec|
  spec.name          = "manageiq-providers-vmware"
  spec.version       = ManageIQ::Providers::Vmware::VERSION
  spec.authors       = ["ManageIQ Authors"]

  spec.summary       = "ManageIQ plugin for the VMware provider."
  spec.description   = "ManageIQ plugin for the VMware provider."
  spec.homepage      = "https://github.com/ManageIQ/manageiq-providers-vmware"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "fog-vcloud-director",    "~> 0.3.0"
  spec.add_dependency "ffi-vix_disk_lib",       "~>1.1"
  spec.add_dependency "rbvmomi2",               "~>3.5"
  spec.add_dependency "vmware_web_service",     "~>3.2"
  spec.add_dependency "vsphere-automation-sdk", "~>0.4.7"

  spec.add_development_dependency "manageiq-style"
  spec.add_development_dependency "simplecov", ">= 0.21.2"
end
