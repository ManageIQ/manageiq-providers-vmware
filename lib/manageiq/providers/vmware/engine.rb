module ManageIQ
  module Providers
    module Vmware
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Vmware

        config.autoload_paths << root.join('lib').to_s

        initializer :append_secrets do |app|
          app.config.paths["config/secrets"] << root.join("config", "secrets.defaults.yml").to_s
          app.config.paths["config/secrets"] << root.join("config", "secrets.yml").to_s
        end

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('VMware Provider')
        end

        def self.seedable_classes
          %w[ManageIQ::Providers::Vmware]
        end

        def self.init_loggers
          $vim_log ||= Vmdb::Loggers.create_logger("vim.log")
          $vcloud_log ||= Vmdb::Loggers.create_logger("vcloud.log")
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $vim_log, :level_vim)
          Vmdb::Loggers.apply_config_value(config, $vcloud_log, :level_vcloud)
        end
      end
    end
  end
end
