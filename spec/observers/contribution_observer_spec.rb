require 'spec_helper'

describe ContributionObserver do
  let!(:project) { create(:project) }
  let(:resource) do
    create(:contribution,
           project:      project,
           state:        resource_state,
           confirmed_at: confirmed_at,
           value:        1000)
  end
  let(:resource_class)   { Contribution }
  let(:resource_name)    { resource_class.model_name.param_key.to_sym }
  let(:resource_id_name) { "#{resource_name}_id".to_sym }
  let(:resource_state)   { 'confirmed' }
  let(:confirmed_at)     { Time.now }

  before do
    Notification.unstub(:notify_once)
  end

  describe '#after_create' do
    describe 'when updating status' do
      let(:resource_state) { 'pending' }

      it 'update project\'s total' do
        resource
        expect_any_instance_of(ProjectTotalBuilder).to receive(:perform)
        resource.confirm!
      end
    end

    it 'update project\'s total' do
      expect_any_instance_of(ProjectTotalBuilder).to receive(:perform)
      resource
    end
  end

  describe '#before_save' do
    context 'when project is already successful' do
      before do
        resource.project = create(:project, state: 'successful')
      end
    end

    context 'when project is already finished' do
      let(:user)           { create(:user, email: ENV['EMAIL_PAYMENTS'].dup) }
      let(:resource_state) { 'pending' }
      let(:confirmed_at)   { nil }

      before do
        resource.project.stub(:expires_at).and_return(8.days.ago)
      end

      it 'notifies backoffice about confirmation' do
        allow(Notification).to receive(:notify_once)
        resource.confirm!
      end
    end
  end
end
