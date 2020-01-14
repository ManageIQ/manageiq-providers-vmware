module ManageIQ::Providers::Vmware::CloudManager::Vm::RemoteConsole
  def console_supported?(type)
    %w(WEBMKS).include?(type.upcase)
  end

  def validate_remote_console_acquire_ticket(protocol, options = {})
    raise(MiqException::RemoteConsoleNotSupportedError, "#{protocol} remote console requires the vm to be registered with a management system.") if ext_management_system.nil?
    options[:check_if_running] = true unless options.key?(:check_if_running)
    raise(MiqException::RemoteConsoleNotSupportedError, "#{protocol} remote console requires the vm to be running.") if options[:check_if_running] && state != "on"
  end

  def remote_console_acquire_ticket(userid, originating_server, protocol)
    send("remote_console_#{protocol.to_s.downcase}_acquire_ticket", userid, originating_server)
  end

  def remote_console_acquire_ticket_queue(protocol, userid)
    task_opts = {
      :action => "Acquiring Vm #{name} #{protocol.to_s.upcase} remote console ticket for user #{userid}",
      :userid => userid
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => 'remote_console_acquire_ticket',
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [userid, MiqServer.my_server.id, protocol]
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  #
  # WebMKS
  #

  def remote_console_webmks_acquire_ticket(userid, originating_server = nil)
    require 'securerandom'

    validate_remote_console_webmks_support
    ticket = nil

    ext_management_system.with_provider_connection do |service|
      ticket = service.post_acquire_mks_ticket(ems_ref).body
    end

    raise(MiqException::RemoteConsoleNotSupportedError, 'Could not obtain WebMKS ticket') unless ticket && ticket[:Ticket]

    SystemConsole.force_vm_invalid_token(id)

    console_args = {
      :user       => User.find_by(:userid => userid),
      :vm_id      => id,
      :ssl        => true,
      :protocol   => 'webmks-uint8utf8',
      :secret     => ticket[:Ticket],
      :url_secret => SecureRandom.hex,
      :url        => "/#{ticket[:Port]};#{ticket[:Ticket]}"
    }
    SystemConsole.launch_proxy_if_not_local(console_args, originating_server, ticket[:Host], 443).update(
      :secret    => 'is-in-url',
      # vCloud specific querystring params
      :is_vcloud => true,
      :vmx       => ticket[:Vmx]
    )
  end

  #
  # HTML5
  #
  alias_method :remote_console_html5_acquire_ticket, :remote_console_webmks_acquire_ticket

  def validate_remote_console_webmks_support
    validate_remote_console_acquire_ticket('webmks')
    if (api_version = ext_management_system.api_version.to_f) && api_version < 5.5
      raise(MiqException::RemoteConsoleNotSupportedError, "vCloud version #{api_version} does not support WebMKS remote console.")
    end
    true
  end
end
