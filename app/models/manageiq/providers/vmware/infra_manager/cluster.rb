class ManageIQ::Providers::Vmware::InfraManager::Cluster < ManageIQ::Providers::InfraManager::Cluster
  include ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin

  def provider_object(connection)
    connection.getVimClusterByMor(ems_ref_obj)
  end

  def provider_object_release(handle)
    handle&.release rescue nil
  end

  def register_host(host)
    host = Host.extract_objects(host)
    raise _("Host cannot be nil") if host.nil?

    userid, password = host.auth_user_pwd(:default)
    network_address  = host.hostname

    with_provider_object do |vim_cluster|
      begin
        _log.info("Invoking addHost with options: address => #{network_address}, #{userid}")
        host_mor = vim_cluster.addHost(network_address, userid, password)
      rescue VimFault => verr
        fault = verr.vimFaultInfo.fault
        raise if     fault.nil?
        raise unless fault.xsiType == "SSLVerifyFault"

        ssl_thumbprint = fault.thumbprint
        _log.info("Invoking addHost with options: address => #{network_address}, userid => #{userid}, sslThumbprint => #{ssl_thumbprint}")
        host_mor = vim_cluster.addHost(network_address, userid, password, :sslThumbprint => ssl_thumbprint)
      end

      host.ems_ref                = host_mor
      host.ext_management_system  = ext_management_system
      host.name                   = "unknown"
      host.save!
      hosts << host
      host.refresh_ems
    end
  end
end
