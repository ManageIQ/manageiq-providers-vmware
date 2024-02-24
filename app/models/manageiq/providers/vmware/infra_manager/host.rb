class ManageIQ::Providers::Vmware::InfraManager::Host < ::Host
  include ManageIQ::Providers::Vmware::InfraManager::VimConnectMixin
  include ManageIQ::Providers::Vmware::InfraManager::EmsRefObjMixin

  supports :capture
  supports :update

  # overrides base start to support "standby" powerstate
  supports :start do
    if %w[off standby].exclude?(power_state)
      _("The Host is not in power state off or standby")
    else
      unsupported_reason(:ipmi)
    end
  end

  def connect(options = {})
    vim_connect(options)
  end

  def start
    if verbose_supports?(:start)
      if power_state == 'standby'
        check_policy_prevent("request_host_start", "vim_power_up_from_standby")
      else
        super
      end
    end
  end

  def provider_object(connection)
    api_type = connection.about["apiType"]
    mor =
      case api_type
      when "VirtualCenter"
        # The ems_ref in the VMDB is from the vCenter perspective
        ems_ref
      when "HostAgent"
        # Since we are going directly to the host, it acts like a VC
        # Thus, there is only a single host in it
        # It has a MOR for itself, which is different from the vCenter MOR
        connection.hostSystemsByMor.keys.first
      else
        raise "Unknown connection API type '#{api_type}'"
      end

    connection.getVimHostByMor(mor)
  end

  def provider_object_release(handle)
    handle.release if handle rescue nil
  end

  def refresh_files_on_datastore(datastore)
    raise _("Host must be connected to an EMS to refresh datastore files") if ext_management_system.nil?
    ext_management_system.refresh_files_on_datastore(datastore)
  end

  def reserve_next_available_vnc_port
    port_start = ext_management_system.try(:host_default_vnc_port_start).try(:to_i) || 5900
    port_end   = ext_management_system.try(:host_default_vnc_port_end).try(:to_i) || 5999

    lock do
      port = next_available_vnc_port
      port = port_start unless port.in?(port_start..port_end)

      next_port = (port == port_end ? port_start : port + 1)
      update(:next_available_vnc_port => next_port)

      port
    end
  end

  supports :quick_stats

  def self.display_name(number = 1)
    n_('Host (Vmware)', 'Hosts (Vmware)', number)
  end

  def params_for_update
    {
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _("Endpoints"),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'ws-tab',
                :name      => 'ws-tab',
                :title     => _('Web Service'),
                :fields    => [
                  {
                    :component  => 'validate-host-credentials',
                    :id         => 'authentications.default.valid',
                    :name       => 'authentications.default.valid',
                    :skipSubmit => true,
                    :isRequired => true,
                    :fields     => [
                      {
                        :component  => "text-field",
                        :id         => "authentications.default.userid",
                        :name       => "authentications.default.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.default.password",
                        :name       => "authentications.default.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :helperText => _('Used for access to Web Services.')
                      },
                    ],
                  },
                ],
              },
              {
                :component => 'tab-item',
                :id        => 'remote-tab',
                :name      => 'remote-tab',
                :title     => _('Remote'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'remoteEnabled',
                    :name         => 'remoteEnabled',
                    :skipSubmit   => true,
                    :initialValue => 'disabled',
                    :label        => _('Enabled'),
                    :options      => [
                      {
                        :label => _('Disabled'),
                        :value => 'disabled'
                      },
                      {
                        :label => _('Enabled'),
                        :value => 'enabled',
                      },
                    ],
                  },
                  {
                    :component  => 'validate-host-credentials',
                    :id         => 'authentications.remote.valid',
                    :name       => 'authentications.remote.valid',
                    :skipSubmit => true,
                    :condition  => {
                      :when => 'remoteEnabled',
                      :is   => 'enabled',
                    },
                    :fields     => [
                      {
                        :component  => "text-field",
                        :id         => "authentications.remote.userid",
                        :name       => "authentications.remote.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.remote.password",
                        :name       => "authentications.remote.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :helperText => _('Used for SSH login.')
                      },
                    ],
                  },
                ],
              },
            ]
          ]
        },
      ]
    }
  end
end
