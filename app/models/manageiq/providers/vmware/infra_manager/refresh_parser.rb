require 'miq-uuid'

module ManageIQ::Providers
  module Vmware
    module InfraManager::RefreshParser
      #
      # Datastore File Inventory Parsing
      #

      def self.datastore_file_inv_to_hashes(inv, vm_ids_by_path)
        return [] if inv.nil?

        result = inv.collect do |data|
          name = data['fullPath']
          is_dir = data['fileType'] == 'FileFolderInfo'
          vm_id = vm_ids_by_path[is_dir ? name : File.dirname(name)]

          new_result = {
            :name      => name,
            :size      => data['fileSize'],
            :base_name => data['path'],
            :ext_name  => File.extname(data['path'])[1..-1].to_s.downcase,
            :mtime     => data['modification'],
            :rsc_type  => is_dir ? 'dir' : 'file'
          }
          new_result[:vm_or_template_id] = vm_id unless vm_id.nil?

          new_result
        end

        result
      end

      #
      # Other
      #

      def self.host_inv_to_firewall_rules_hashes(inv)
        inv = inv.fetch_path('config', 'firewall', 'ruleset')

        result = []
        return result if inv.nil?

        Array.wrap(inv).each do |data|
          # Collect Rule Set values
          current_rule_set = {:group => data['key'], :enabled => data['enabled'], :required => data['required']}

          # Process each Firewall Rule
          data['rule'].each do |rule|
            rule_string = rule['endPort'].nil? ? rule['port'].to_s : "#{rule['port']}-#{rule['endPort']}"
            rule_string << " (#{rule['protocol']}-#{rule['direction']})"
            result << {
              :name          => "#{data['key']} #{rule_string}",
              :display_name  => "#{data['label']} #{rule_string}",
              :host_protocol => rule['protocol'],
              :direction     => rule['direction'].chomp('bound'),  # Turn inbound/outbound to just in/out
              :port          => rule['port'],
              :end_port      => rule['endPort'],
            }.merge(current_rule_set)
          end
        end
        result
      end

      def self.host_inv_to_advanced_settings_hashes(inv)
        inv = inv['config']

        result = []
        return result if inv.nil?

        settings = Array.wrap(inv['option']).index_by { |o| o['key'] }
        details = Array.wrap(inv['optionDef']).index_by { |o| o['key'] }

        settings.each do |key, setting|
          detail = details[key]

          # TODO: change the 255 length 'String' columns, truncated below, to text
          # A vmware string type was confirmed to allow up to 9932 bytes
          result << {
            :name          => key,
            :value         => setting['value'].to_s,
            :display_name  => detail.nil? ? nil : truncate_value(detail['label']),
            :description   => detail.nil? ? nil : truncate_value(detail['summary']),
            :default_value => detail.nil? ? nil : truncate_value(detail.fetch_path('optionType', 'defaultValue')),
            :min           => detail.nil? ? nil : truncate_value(detail.fetch_path('optionType', 'min')),
            :max           => detail.nil? ? nil : truncate_value(detail.fetch_path('optionType', 'max')),
            :read_only     => detail.nil? ? nil : detail.fetch_path('optionType', 'valueIsReadonly')
          }
        end
        result
      end

      def self.truncate_value(val)
        return val[0, 255] if val.kind_of?(String)
      end
    end
  end
end
