require 'spec_helper'

describe ProjectFinancialsByService do
  subject { described_class.new(project) }
  let(:project) { create(:project, state: 'online') }

  describe 'net amount' do
    before do
      create(
        :contribution,
        value:               100,
        payment_method:      'balanced',
        project:             project,
        state:               'confirmed'
      )
    end

    it 'sums contributions values' do
      expect(subject.net_amount.to_f).to eql(100.0)
    end

    it 'does not take non confirmed contributions in count' do
      create(
        :contribution,
        value:               100,
        payment_method:      'balanced',
        payment_service_fee: 1,
        project:             project,
        state:               'waiting_confirmation'
      )
      expect(subject.net_amount.to_f).to eql(100.0)
    end
  end
end
