require 'parser/current'

RSpec.describe "Worker Gemfile Sync" do
  let(:worker_file_path) { ManageIQ::Providers::Vmware::Engine.root.join("workers/event_catcher/worker") }
  let(:gemfile_lock_path) { ManageIQ::Providers::Vmware::Engine.root.join("Gemfile.lock") }

  def parse_inline_gemfile(file_path)
    content = File.read(file_path)

    # Parse the Ruby file into an AST
    buffer = Parser::Source::Buffer.new(file_path.to_s)
    buffer.source = content
    parser = Parser::CurrentRuby.new
    ast = parser.parse(buffer)

    # Find the gemfile block and extract gem declarations
    gems = {:required => {}, :conditional => {}}

    # Traverse the AST to find the gemfile block
    find_gemfile_block(ast, gems)

    gems
  end

  def find_gemfile_block(node, gems, in_conditional: false, condition: nil)
    return unless node.kind_of?(Parser::AST::Node)

    # Look for method calls to 'gem'
    if node.type == :send && node.children[1] == :gem
      gem_name = node.children[2]&.children&.first
      gem_version = node.children[3]&.children&.first

      if gem_name
        if in_conditional
          gems[:conditional][gem_name] = {:version => gem_version, :condition => condition}
        else
          gems[:required][gem_name] = gem_version
        end
      end
    end

    # Look for conditional blocks (if ENV.fetch(...))
    if node.type == :if
      condition_node = node.children[0]
      # Check if this is an ENV.fetch call
      if condition_node.type == :send &&
         condition_node.children[0]&.type == :const &&
         condition_node.children[0]&.children&.last == :ENV &&
         condition_node.children[1] == :fetch

        env_var = condition_node.children[2]&.children&.first
        # Process the then branch (body of the if)
        then_branch = node.children[1]
        find_gemfile_block(then_branch, gems, :in_conditional => true, :condition => env_var)
        return
      end
    end

    # Recursively process child nodes
    node.children.each do |child|
      find_gemfile_block(child, gems, :in_conditional => in_conditional, :condition => condition)
    end
  end

  def parse_gemfile_lock(file_path)
    lockfile = Bundler::LockfileParser.new(File.read(file_path))
    gems = lockfile.specs.to_h do |spec|
      [spec.name, spec.version.to_s]
    end
    raise "Could not find any gems in #{file_path}" if gems.empty?

    gems
  end

  def validate_gem_version(gem_name, requirement, installed_version)
    # No version constraint means any version is acceptable
    return {:valid => true, :message => "No version constraint"} if requirement.blank?

    # Gem not found in Gemfile.lock
    if installed_version.nil?
      return {
        :valid   => false,
        :message => "Gem '#{gem_name}' not found in Gemfile.lock"
      }
    end

    # Check if installed version satisfies the requirement
    begin
      req = Gem::Requirement.new(requirement)
      ver = Gem::Version.new(installed_version)

      if req.satisfied_by?(ver)
        {:valid => true, :message => "Version #{installed_version} satisfies #{requirement}"}
      else
        {
          :valid   => false,
          :message => "Installed version #{installed_version} does not satisfy requirement #{requirement}"
        }
      end
    rescue ArgumentError => e
      {
        :valid   => false,
        :message => "Invalid version format: #{e.message}"
      }
    end
  end

  describe "inline gemfile gems" do
    it "matches versions in Gemfile.lock" do
      # Parse both files
      inline_gems = parse_inline_gemfile(worker_file_path)
      installed_gems = parse_gemfile_lock(gemfile_lock_path)

      # Collect validation results
      mismatches = []

      # Validate required gems (non-conditional)
      inline_gems[:required].each do |gem_name, version_requirement|
        result = validate_gem_version(gem_name, version_requirement, installed_gems[gem_name])

        next if result[:valid]

        mismatches << {
          :gem       => gem_name,
          :required  => version_requirement || "any",
          :installed => installed_gems[gem_name] || "not found",
          :reason    => result[:message]
        }
      end

      # Validate conditional gems (only report if they exist in Gemfile.lock)
      # We don't fail if they're missing since they're conditional
      inline_gems[:conditional].each do |gem_name, gem_info|
        next unless installed_gems[gem_name] # Skip if not installed (conditional)

        result = validate_gem_version(gem_name, gem_info[:version], installed_gems[gem_name])

        next if result[:valid]

        mismatches << {
          :gem         => gem_name,
          :required    => gem_info[:version] || "any",
          :installed   => installed_gems[gem_name],
          :reason      => result[:message],
          :conditional => gem_info[:condition]
        }
      end

      # Build error message if there are mismatches
      if mismatches.any?
        error_message = "\n\nGem version mismatches found between worker inline gemfile and Gemfile.lock:\n\n"

        mismatches.each do |mismatch|
          error_message += "  • #{mismatch[:gem]}:\n"
          error_message += "      Required: #{mismatch[:required]}\n"
          error_message += "      Installed: #{mismatch[:installed]}\n"
          error_message += "      Reason: #{mismatch[:reason]}\n"
          error_message += "      Conditional: #{mismatch[:conditional]}\n" if mismatch[:conditional]
          error_message += "\n"
        end

        error_message += "Please update the inline gemfile in workers/event_catcher/worker to match Gemfile.lock\n"
        error_message += "or update Gemfile.lock by running 'bundle update <gem_name>'\n"

        raise error_message
      end

      # If we get here, all gems match
      expect(mismatches).to be_empty
    end
  end
end
