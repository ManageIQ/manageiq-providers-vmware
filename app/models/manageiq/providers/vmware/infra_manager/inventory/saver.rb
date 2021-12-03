class ManageIQ::Providers::Vmware::InfraManager::Inventory::Saver
  include Vmdb::Logging

  class << self
    def save_inventory(persister)
      save_inventory_start_time = Time.now.utc
      persister.persist!
      update_ems_refresh_stats(persister.manager)
      post_refresh(persister.manager, save_inventory_start_time)
    rescue => err
      log_header = log_header_for_ems(persister.manager)

      _log.error("#{log_header} Save Inventory failed")
      _log.log_backtrace(err)

      update_ems_refresh_stats(persister.manager, :error => err.to_s)
    end

    private

    def update_ems_refresh_stats(ems, error: nil)
      ems.update(:last_refresh_error => error, :last_refresh_date => Time.now.utc)
    end

    def post_refresh(ems, save_inventory_start_time)
      log_header = log_header_for_ems(ems)

      # Do any post-operations for this EMS
      post_process_refresh_classes.each do |klass|
        next unless klass.respond_to?(:post_refresh_ems)

        _log.info("#{log_header} Performing post-refresh operations for #{klass} instances...")
        klass.post_refresh_ems(ems.id, save_inventory_start_time)
        _log.info("#{log_header} Performing post-refresh operations for #{klass} instances...Complete")
      end
    end

    def post_process_refresh_classes
      [VmOrTemplate]
    end

    def log_header_for_ems(ems)
      "EMS: [#{ems.name}], id: [#{ems.id}]"
    end
  end
end
