class ManageIQ::Providers::Vmware::InfraManager::Folder < ManageIQ::Providers::InfraManager::Folder
  include ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin
  #
  # Provider Object methods
  #
  def provider_object(connection)
    connection.getVimFolderByMor(ems_ref_obj)
  end

  def provider_object_release(handle)
    handle.release if handle rescue nil
  end

  def register_host(host)
    host = Host.extract_objects(host)
    raise _("Host cannot be nil") if host.nil?
    userid, password = host.auth_user_pwd(:default)
    network_address  = host.address

    with_provider_connection do |vim|
      handle = provider_object(vim)
      begin
        _log.info("Invoking addStandaloneHost with options: address => #{network_address}, #{userid}")
        cr_mor = handle.addStandaloneHost(network_address, userid, password)
      rescue VimFault => verr
        fault = verr.vimFaultInfo.fault
        raise if     fault.nil?
        raise unless fault.xsiType == "SSLVerifyFault"

        ssl_thumbprint = fault.thumbprint
        _log.info("Invoking addStandaloneHost with options: address => #{network_address}, userid => #{userid}, sslThumbprint => #{ssl_thumbprint}")
        cr_mor = handle.addStandaloneHost(network_address, userid, password, :sslThumbprint => ssl_thumbprint)
      end

      host_mor                   = vim.computeResourcesByMor[cr_mor].host.first
      host.ems_ref               = host_mor
      host.ems_ref_obj           = host_mor
      host.ext_management_system = ext_management_system
      host.save!
      add_host(host)
      host.refresh_ems
    end
  end
end
