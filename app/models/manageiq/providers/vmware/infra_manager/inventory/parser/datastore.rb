class ManageIQ::Providers::Vmware::InfraManager::Inventory::Parser
  module Datastore
    def parse_datastore_summary(storage_hash, props)
      summary = props[:summary]
      return if summary.nil?

      storage_hash[:name] = summary[:name]
      storage_hash[:location] = parse_datastore_location(props)
      storage_hash[:store_type] = summary[:type].to_s.upcase
      storage_hash[:total_space] = summary[:capacity]
      storage_hash[:free_space] = summary[:freeSpace]
      storage_hash[:uncommitted] = summary[:uncommitted]
      storage_hash[:multiplehostaccess] = summary[:multipleHostAccess].to_s.downcase == "true"
    end

    def parse_datastore_location(props)
      url = props.fetch_path(:summary, :url)
      normalize_storage_uid(url) if url
    end

    def parse_datastore_capability(storage_hash, props)
      capability = props[:capability]
      return if capability.nil?

      storage_hash[:directory_hierarchy_supported] = capability[:directoryHierarchySupported].to_s.downcase == 'true'
      storage_hash[:thin_provisioning_supported] = capability[:perFileThinProvisioningSupported].to_s.downcase == 'true'
      storage_hash[:raw_disk_mappings_supported] = capability[:rawDiskMappingsSupported].to_s.downcase == 'true'
    end

    def parse_datastore_host_mount(storage, datastore_ref, props)
      props[:host].to_a.each do |host_mount|
        read_only  = host_mount.mountInfo.accessMode == "readOnly"
        accessible = host_mount.mountInfo.accessible.present? ? host_mount.mountInfo.accessible : true

        # For backport purposes where we do not have the host_storages.accessible
        # column we can override the read_only column to prevent inaccessible
        # datastore from being selected for provisioning.
        read_only ||= !accessible

        persister.host_storages.build(
          :storage   => storage,
          :host      => persister.hosts.lazy_find(host_mount.key._ref),
          :ems_ref   => datastore_ref,
          :read_only => read_only,
        )
      end
    end

    private

    def normalize_storage_uid(summary_url)
      ############################################################################
      # For VMFS, we will use the GUID as the identifier
      ############################################################################

      # VMFS has the GUID in the url:
      #   From VC4:  sanfs://vmfs_uuid:49861d7d-25f008ac-ffbf-001b212bed24/
      #   From VC5:  ds:///vmfs/volumes/49861d7d-25f008ac-ffbf-001b212bed24/
      #   From ESX4: /vmfs/volumes/49861d7d-25f008ac-ffbf-001b212bed24
      url = summary_url.to_s.downcase
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

      # For anything else, we return the url
      url
    end
  end
end
