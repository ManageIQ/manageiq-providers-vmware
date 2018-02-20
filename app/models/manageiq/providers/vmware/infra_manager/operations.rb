require "sinatra/base"

class ManageIQ::Providers::Vmware::InfraManager::Operations < Sinatra::Base
  require_nested :Connection

  disable :traps

  def initialize
    super

    @connections      = Concurrent::Map.new
    @connection_class = self.class::Connection
  end

  def shutdown
    connections.each_value(&:close)
  end

  private

  attr_reader :connections, :connection_class

  def with_provider_connection
    raise "Invalid connection parameters" unless validate_connection_params

    connections.compute_if_absent(connection_key) { connection_class.new(*connection_params) }.with { |conn| yield conn }
  end

  def connection_param_keys
    %i(server username password)
  end

  def connection_params
    params.values_at(*connection_param_keys)
  end

  def connection_key
    server, username, _ = connection_params
    "#{server}__#{username}"
  end

  def validate_connection_params
    server, user, password = connection_params
    server && user && password
  end
end
