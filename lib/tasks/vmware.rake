namespace :update do
  desc "Build the Go event catcher worker (workers/event_catcher/worker)"
  task :workers => :environment do
    Dir.chdir(File.expand_path("../../workers/event_catcher", __dir__)) do
      system("make build") || abort("\n== make build failed for the vmware event catcher ==")
    end
  end
end
