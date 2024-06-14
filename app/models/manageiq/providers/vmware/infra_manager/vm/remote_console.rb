module ManageIQ::Providers::Vmware::InfraManager::Vm::RemoteConsole
  extend ActiveSupport::Concern

  included do
    supports :console do
      if ext_management_system.nil?
        "VM must be registered with a management system."
      elsif state != "on"
        "VM must be running."
      end
    end
    supports(:html5_console) { unsupported_reason(:console) }
    supports :vmrc_console do
      unsupported_reason(:console) ||
        ext_management_system.unsupported_reason(:vmrc_console)
    end
    supports :vnc_console { unsupported_reason(:console) }
    supports :webmks_console do
      unsupported_reason(:console) ||
        ext_management_system.unsupported_reason(:webmks_console)
    end
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
    validate_supports(:vmrc_console)
    ticket = ext_management_system.remote_console_vmrc_acquire_ticket

    {
      :ticket     => ticket.to_s, # Ensure ticket is a basic String not a VimString
      :remote_url => build_vmrc_url(ticket),
      :proto      => 'remote'
    }
  end

  #
  # WebMKS
  #

  def remote_console_webmks_acquire_ticket(userid, originating_server = nil)
    validate_supports(:webmks_console)
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

  #
  # HTML5 selects the best available console type (VNC or WebMKS)
  #
  def remote_console_html5_acquire_ticket(userid, originating_server = nil)
    protocol = with_provider_object { |v| v.extraConfig["RemoteDisplay.vnc.enabled"] == "true" } ? 'vnc' : 'webmks'
    send("remote_console_#{protocol}_acquire_ticket", userid, originating_server)
  end

  #
  # VNC
  #
  def remote_console_vnc_acquire_ticket(userid, originating_server)
    require 'securerandom'

    validate_supports(:vnc_console)

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

  def validate_supports(feature)
    if (unsupported_reason = unsupported_reason(feature))
      raise(MiqException::RemoteConsoleNotSupportedError, unsupported_reason)
    end
  end

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
