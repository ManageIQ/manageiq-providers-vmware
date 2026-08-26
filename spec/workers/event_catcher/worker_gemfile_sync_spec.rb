require 'prism'

RSpec.describe "Worker Gemfile Sync" do
  let(:worker_file_path) { ManageIQ::Providers::Vmware::Engine.root.join("workers/event_catcher/worker") }
  let(:gemfile_lock_path) { ManageIQ::Providers::Vmware::Engine.root.join("Gemfile.lock") }

  def parse_inline_gemfile(file_path)
    # Parse the Ruby file into an AST using Prism
    result = Prism.parse_file(file_path.to_s)
    ast = result.value

    # Find the gemfile block and extract gem declarations
    gems = {:required => {}, :conditional => {}}

    # Traverse the AST to find the gemfile block
    find_gemfile_block(ast, gems)

    gems
  end

  def find_gemfile_block(node, gems, in_conditional: false, condition: nil)
    return unless node.kind_of?(Prism::Node)

    # Look for method calls to 'gem'
    if node.kind_of?(Prism::CallNode) && node.name == :gem
      # Extract gem name from first argument
      gem_name = nil
      gem_version = nil

      if node.arguments && !node.arguments.arguments.empty?
        first_arg = node.arguments.arguments[0]
        gem_name = first_arg.unescaped if first_arg.kind_of?(Prism::StringNode)

        # Extract version from second argument if present
        if node.arguments.arguments.length > 1
          second_arg = node.arguments.arguments[1]
          gem_version = second_arg.unescaped if second_arg.kind_of?(Prism::StringNode)
        end
      end

      if gem_name
        if in_conditional
          gems[:conditional][gem_name] = {:version => gem_version, :condition => condition}
        else
          gems[:required][gem_name] = gem_version
        end
      end
    end

    # Look for conditional blocks (if ENV.fetch(...))
    if node.kind_of?(Prism::IfNode)
      predicate = node.predicate

      # Check if this is an ENV.fetch call
      if predicate.kind_of?(Prism::CallNode) &&
         predicate.receiver.kind_of?(Prism::ConstantReadNode) &&
         predicate.receiver.name == :ENV &&
         predicate.name == :fetch

        # Extract the environment variable name
        env_var = nil
        if predicate.arguments && !predicate.arguments.arguments.empty?
          first_arg = predicate.arguments.arguments[0]
          env_var = first_arg.unescaped if first_arg.kind_of?(Prism::StringNode)
        end

        # Process the then branch (statements of the if)
        if node.statements
          find_gemfile_block(node.statements, gems, :in_conditional => true, :condition => env_var)
        end
        return
      end
    end

    # Recursively process child nodes
    node.compact_child_nodes.each do |child|
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
