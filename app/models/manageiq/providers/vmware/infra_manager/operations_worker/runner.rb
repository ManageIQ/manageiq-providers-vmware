class ManageIQ::Providers::Vmware::InfraManager::OperationsWorker::Runner < ManageIQ::Providers::BaseManager::OperationsWorker::Runner
  attr_reader :miq_vim

  def do_before_work_loop
    server = ems.hostname
    username, password = ems.auth_user_pwd
    cache_scope = :cache_scope_core

    require "VMwareWebService/MiqVim"
    @miq_vim = MiqVim.new(server, username, password, cache_scope)
  end

  def deliver_queue_message(msg)
    super do |obj, args|
      if args.first&.kind_of?(Hash)
        args.first[:vim] = miq_vim
      else
        args << miq_vim
      end
      obj.send(msg.method_name, *args)
    end
  end
end
