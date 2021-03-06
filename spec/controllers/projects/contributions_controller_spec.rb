require 'spec_helper'

describe Projects::ContributionsController do
  let(:project) { create(:project) }
  let(:contribution){ create(:contribution, value: 10.00, project: project, state: 'pending') }
  let(:user){ nil }
  let(:contribution_info){ { address_city: 'Porto Alegre', address_complement: '24', address_neighborhood: 'Rio Branco', address_number: '1004', address_phone_number: '(51)2112-8397', address_state: 'RS', address_street: 'Rua Mariante', address_zip_code: '90430-180', payer_email: 'diogo@biazus.me', payer_name: 'Diogo de Oliveira Biazus' } }

  subject{ response }

  before do
    controller.stub(:current_user).and_return(user)
  end

  describe "GET edit" do
    before do
      get :edit, {locale: :pt, project_id: project, id: contribution.id}
    end

    context "when no user is logged" do
      it{ should redirect_to new_user_session_path }
      it('should set the session[:return_to]'){ session[:return_to].should == edit_project_contribution_url(project_id: project, id: contribution.id) }
    end

    context "when user is logged in" do
      render_views

      let(:user){ create(:user) }
      let(:contribution){ create(:contribution, value: 10.00, project: project, state: 'pending', user: user) }
      its(:body){ should =~ /#{I18n.t('projects.contributions.edit.title', project_name: project.name)}/ }
      its(:body){ should =~ /#{project.name}/ }
    end

    describe 'persistent warnings' do
      let(:set_expectations) do
        expect(controller).to_not receive(:set_persistent_warning)
      end

      it 'skips its setter method call' do
      end
    end
  end

  describe "POST create" do
    let(:value){ '20.00' }
    let(:set_expectations) {}
    before do
      set_expectations
      post :create, project_id: project, contribution: { value: value, reward_id: nil, anonymous: '0', bonds: '3' }
    end

    context "when no user is logged" do
      it{ should redirect_to new_user_session_path }
      it('should set the session[:return_to]'){ session[:return_to].should == project_contributions_url(project_id: project) }
    end

    context "when user is logged in" do
      let(:user){ create(:user) }
      it{ should redirect_to edit_project_contribution_path(project_id: project, id: Contribution.last.id) }
    end

    context "without value" do
      let(:user){ create(:user) }
      let(:value){ '' }

      it{ should redirect_to new_project_contribution_path(project) }
    end

    describe 'persistent warnings' do
      let(:set_expectations) do
        expect(controller).to_not receive(:set_persistent_warning)
      end

      it 'skips its setter method call' do
      end
    end
  end

  describe "GET new" do
    let(:user){ create(:user) }
    let(:online){ true }
    let(:browser){ double("browser", ie9?: false, modern?: true) }

    before do
      Project.any_instance.stub(:online?).and_return(online)
      get :new, {locale: :pt, project_id: project}
    end

    context "when no user is logged" do
      let(:user){ nil }
      it{ should redirect_to new_user_session_path }
    end

    context "when user is logged in but project.online? is false" do
      let(:online){ false }
      it{ should redirect_to root_path }
    end


    context "when project.online? is true and we have not configured a secure create url" do
      render_views

      it{ should render_template("projects/contributions/new") }

      its(:body) { should =~ /#{I18n.t('projects.contributions.new.title')}/ }
      its(:body) { should =~ /#{project.name}/ }
    end

    describe 'persistent warnings' do
      let(:set_expectations) do
        expect(controller).to_not receive(:set_persistent_warning)
      end

      it 'skips its setter method call' do
      end
    end
  end

  describe "GET show" do
    let(:contribution){ create(:contribution, value: 10.00, state: 'confirmed') }
    before do
      get :show, { locale: :pt, project_id: contribution.project, id: contribution.id }
    end

    context "when no user is logged in" do
      it{ should redirect_to new_user_session_path }
    end

    context "when user logged in is different from contribution" do
      let(:user){ create(:user) }
      it{ should redirect_to root_path }
      it('should set flash failure'){ request.flash.alert.should_not be_empty }
    end

    context "when contribution is logged in" do
      render_views

      let(:user){ contribution.user }
      it{ should be_successful }
      its(:body){ should =~ /#{I18n.t('projects.contributions.show.title')}/ }
    end
  end

  describe "GET index" do
    before do
      create(:contribution, value: 10.00, state: 'confirmed',
              reward: create(:reward, project: project),
              project: project,
              user: create(:user, name: 'Foo Bar'))
    end

    it 'responds with 200 HTTP status' do
      get :index, locale: :pt, project_id: project
      expect(subject.status).to eq(200)
    end
  end
end
