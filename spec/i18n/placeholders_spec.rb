describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Vmware::Engine.root.join('locale').to_s
end
