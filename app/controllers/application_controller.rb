class ApplicationController < ActionController::Base
  include Concerns::ExceptionHandler
  include Concerns::SocialHelpersHandler
  include Concerns::PersistentWarnings
  include Concerns::AuthenticationHandler
  include Pundit

  protect_from_forgery

  before_action :store_referral_code

  before_filter do
    if current_user and (current_user.email =~ /change-your-email\+[0-9]+@neighbor\.ly/)
      redirect_to set_email_users_path unless controller_name =~ /users|confirmations/
    end
  end

  def referral_code
    session[:referral_code]
  end

  private

  def store_referral_code
    session[:referral_code] ||= params[:ref]
  end
end
