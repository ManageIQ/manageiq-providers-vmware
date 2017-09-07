class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module Datastore
    def parse_datastore_summary(storage_hash, props)
      if props.include?("summary.name")
        storage_hash[:name] = props["summary.name"]
      end
      if props.include?("summary.url")
        storage_hash[:location] = normalize_storage_uid(props["summary.url"])
      end
      if props.include?("summary.type")
        storage_hash[:store_type] = props["summary.type"].to_s.upcase
      end
      if props.include?("summary.capacity")
        storage_hash[:total_space] = props["summary.capacity"]
      end
      if props.include?("summary.freeSpace")
        storage_hash[:free_space] = props["summary.freeSpace"]
      end
      if props.include?("summary.uncommitted")
        storage_hash[:uncommitted] = props["summary.uncommitted"]
      end
      if props.include?("summary.multipleHostAccess")
        storage_hash[:multiplehostaccess] = props["summary.multipleHostAccess"] ? 1 : 0 # TODO: why is this an integer?
      end
    end

    def parse_datastore_capability(storage_hash, props)
      if props.include?("capability.directoryHierarchySupported")
        storage_hash[:directory_hierarchy_supported] = props["capability.directoryHierarchySupported"]
      end
      if props.include?("capability.perFileThinProvisioningSupported")
        storage_hash[:thin_provisioning_supported] = props["capability.perFileThinProvisioningSupported"]
      end
      if props.include?("capability.rawDiskMappingsSupported")
        storage_hash[:raw_disk_mappings_supported] = props["capability.rawDiskMappingsSupported"]
      end
    end

    def parse_datastore_host_mount(storage, datastore_ref, props)
      return unless props.include?("host")

      props["host"].to_a.each do |host_mount|
        persister.host_storages.build(
          :storage   => storage,
          :host      => persister.hosts.lazy_find(host_mount.key._ref),
          :ems_ref   => datastore_ref,
          :read_only => host_mount.mountInfo.accessMode == "readOnly",
        )
      end
    end

    private

    def normalize_storage_uid(inv)
      ############################################################################
      # For VMFS, we will use the GUID as the identifier
      ############################################################################

      # VMFS has the GUID in the url:
      #   From VC4:  sanfs://vmfs_uuid:49861d7d-25f008ac-ffbf-001b212bed24/
      #   From VC5:  ds:///vmfs/volumes/49861d7d-25f008ac-ffbf-001b212bed24/
      #   From ESX4: /vmfs/volumes/49861d7d-25f008ac-ffbf-001b212bed24
      url = inv["summary.url"].to_s.downcase
      return $1 if url =~ /([0-9a-f]{8}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{12})/

      ############################################################################
      # For NFS on VC5, we will use the "half GUID" as the identifier
      # For other NFS, we will use a path as the identifier in the form: ipaddress/path/parts
      ############################################################################

      # NFS on VC5 has the "half GUID" in the url:
      #   ds:///vmfs/volumes/18f2f698-aae589d5/
      return $1 if url[0, 5] == "ds://" && url =~ /([0-9a-f]{8}-[0-9a-f]{8})/

      # NFS on VC has a path in the url:
      #   netfs://192.168.254.80//shares/public/
      return url[8..-1].gsub('//', '/').chomp('/') if url[0, 8] == "netfs://"

      # NFS on ESX has the path in the datastore instead:
      #   192.168.254.80:/shares/public
      datastore = inv["summary.datastore"].to_s.downcase
      return datastore.gsub(':/', '/') if datastore =~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/

      # For anything else, we return the url
      url
    end
  end
end
