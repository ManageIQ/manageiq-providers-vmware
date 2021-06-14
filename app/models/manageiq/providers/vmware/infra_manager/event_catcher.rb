class ManageIQ::Providers::Vmware::InfraManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner

  def self.unit_file
    <<~UNIT_FILE
      [Unit]
      PartOf=#{target_file_name}
      [Install]
      WantedBy=#{target_file_name}
      [Service]
      WorkingDirectory=#{working_directory}
      ExecStart=/bin/bash -lc '#{exec_start}'
      Restart=always
      Slice=#{slice_name}
    UNIT_FILE
  end

  def self.working_directory
    ManageIQ::Providers::Vmware::Engine.root.join("workers/event_catcher")
  end

  def self.exec_start
    "exec bundle exec ruby event_catcher.rb"
  end

  def unit_environment_variables
    username, password = ext_management_system.auth_user_pwd

    super + [
      "APP_ROOT=#{Rails.root}",
      "HOSTNAME=#{ext_management_system.hostname}",
      "USERNAME=#{username}",
      "PASSWORD=#{ManageIQ::Password.encrypt(password)}",
      "MESSAGING_HOST=localhost",
      "MESSAGING_PORT=9092"
    ]
  end
end
