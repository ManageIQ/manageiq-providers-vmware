require 'bundler'

RSpec.describe 'container event catcher worker inline gems' do
  let(:worker_path) { File.expand_path('../../../workers/container_event_catcher/worker', __dir__) }
  let(:lockfile_path) { File.expand_path('../../../Gemfile.lock', __dir__) }
  let(:lockfile)      { Bundler::LockfileParser.new(Bundler.read_file(lockfile_path)) }

  it 'uses versions compatible with Gemfile.lock', :skip => !File.exist?(File.expand_path('../../../Gemfile.lock', __dir__)) do
    source = File.read(worker_path)
    gems   = source.scan(/gem ['"]([^'"]+)['"], ['"]([^'"]+)['"]/).to_h

    gems.each do |name, requirement|
      locked = lockfile.specs.find { |spec| spec.name == name }
      next unless locked

      expect(Gem::Requirement.new(requirement).satisfied_by?(locked.version)).to(
        be(true),
        "#{name} #{requirement} is not satisfied by locked version #{locked.version}"
      )
    end
  end
end
