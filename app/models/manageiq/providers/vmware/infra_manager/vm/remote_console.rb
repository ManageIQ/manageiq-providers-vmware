module ManageIQ::Providers::Vmware::InfraManager::Vm::RemoteConsole
  def console_supported?(type)
    %w(VMRC VNC WEBMKS).include?(type.upcase)
  end

  def validate_remote_console_acquire_ticket(protocol, options = {})
    raise(MiqException::RemoteConsoleNotSupportedError, "#{protocol} remote console requires the vm to be registered with a management system.") if ext_management_system.nil?

    raise(MiqException::RemoteConsoleNotSupportedError, "remote console requires console credentials") if ext_management_system.authentication_type(:console).nil? && protocol == "vmrc"

    options[:check_if_running] = true unless options.key?(:check_if_running)
    raise(MiqException::RemoteConsoleNotSupportedError, "#{protocol} remote console requires the vm to be running.") if options[:check_if_running] && state != "on"
  end

  def remote_console_acquire_ticket(userid, originating_server, protocol)
    send("remote_console_#{protocol.to_s.downcase}_acquire_ticket", userid, originating_server)
  end

  def remote_console_acquire_ticket_queue(protocol, userid)
    task_opts = {
      :action => "acquiring Vm #{name} #{protocol.to_s.upcase} remote console ticket for user #{userid}",
      :userid => userid
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => 'remote_console_acquire_ticket',
      :queue_name  => queue_name_for_ems_operations,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [userid, MiqServer.my_server.id, protocol]
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  #
  # VMRC
  #

  def remote_console_vmrc_acquire_ticket(_userid = nil, _originating_server = nil)
    validate_remote_console_acquire_ticket("vmrc")
    ticket = ext_management_system.remote_console_vmrc_acquire_ticket

    {
      :ticket     => ticket.to_s, # Ensure ticket is a basic String not a VimString
      :remote_url => build_vmrc_url(ticket),
      :proto      => 'remote'
    }
  end

  def validate_remote_console_vmrc_support
    validate_remote_console_acquire_ticket("vmrc")
    ext_management_system.validate_remote_console_vmrc_support
    true
  end

  #
  # WebMKS
  #

  def remote_console_webmks_acquire_ticket(userid, originating_server = nil)
    validate_remote_console_acquire_ticket("webmks")
    ticket = ext_management_system.vm_remote_console_webmks_acquire_ticket(self)

    SystemConsole.force_vm_invalid_token(id)

    console_args = {
      :user       => User.find_by(:userid => userid),
      :vm_id      => id,
      :ssl        => true,
      :protocol   => 'webmks',
      :secret     => ticket['ticket'].to_s, # Ensure ticket is a basic String not a VimString
      :url_secret => SecureRandom.hex,
    }

    SystemConsole.launch_proxy_if_not_local(console_args, originating_server, ticket['host'].to_s, ticket['port'].to_i)
  end

  def validate_remote_console_webmks_support
    validate_remote_console_acquire_ticket("webmks")
    ext_management_system.validate_remote_console_webmks_support
    true
  end

  #
  # HTML5 selects the best available console type (VNC or WebMKS)
  #
  def remote_console_html5_acquire_ticket(userid, originating_server = nil)
    protocol = 'vnc' if ext_management_system.api_version.to_f < 6.0 # Force VNC protocol for API version lower than 6.0
    protocol ||= with_provider_object { |v| v.extraConfig["RemoteDisplay.vnc.enabled"] == "true" } ? 'vnc' : 'webmks'
    send("remote_console_#{protocol}_acquire_ticket", userid, originating_server)
  end

  #
  # VNC
  #
  def remote_console_vnc_acquire_ticket(userid, originating_server)
    require 'securerandom'

    validate_remote_console_acquire_ticket("vnc")

    password     = SecureRandom.base64[0, 8] # Random password from the Base64 character set
    host_port    = host.reserve_next_available_vnc_port

    # Determine if any Vms on this Host already have this port, and if so, disable them
    old_vms = host.vms_and_templates.where(:vnc_port => host_port)
    old_vms.each do |old_vm|
      _log.info "Disabling VNC on #{old_vm.class.name} id: [#{old_vm.id}] name: [#{old_vm.name}], since the port is being reused."
      old_vm.with_provider_object do |vim_vm|
        vim_vm.setRemoteDisplayVncAttributes(:enabled => false, :port => nil, :password => nil)
      end
    end
    old_vms.update_all(:vnc_port => nil)

    # Enable on this Vm with the requested port and random password
    _log.info "Enabling VNC on #{self.class.name} id: [#{id}] name: [#{name}]"
    with_provider_object do |vim_vm|
      vim_vm.setRemoteDisplayVncAttributes(:enabled => true, :port => host_port, :password => password)
    end
    update(:vnc_port => host_port)

    SystemConsole.force_vm_invalid_token(id)

    console_args = {
      :user       => User.find_by(:userid => userid),
      :vm_id      => id,
      :ssl        => false,
      :protocol   => 'vnc',
      :secret     => password,
      :url_secret => SecureRandom.hex
    }
    host_address = host.hostname

    SystemConsole.launch_proxy_if_not_local(console_args, originating_server, host_address, host_port)
  end

  private

  # Method to generate the remote URI for the VMRC console
  def build_vmrc_url(ticket)
    url = URI::Generic.build(:scheme   => "vmrc",
                             :userinfo => "clone:#{ticket}",
                             :host     => ext_management_system.hostname || ext_management_system.ipaddress,
                             :port     => 443,
                             :path     => "/",
                             :query    => "moid=#{ems_ref}").to_s
    # VMRC doesn't like brackets around IPv6 addresses
    url.sub(/(.*)\[/, '\1').sub(/(.*)\]/, '\1')
  end
end
