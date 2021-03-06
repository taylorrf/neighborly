# coding: utf-8
require 'state_machine'

class User < ActiveRecord::Base
  include User::Completeness,
          Shared::LocationHandler,
          PgSearch
  # Include default devise modules. Others available are:
  # :token_authenticatable, :encryptable, :lockable, :timeoutable and :omniauthable
  # :validatable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :trackable, :omniauthable, :confirmable

  delegate :display_name, :display_image, :short_name, :display_image_html,
    :medium_name, :display_total_of_contributions, :first_name, :last_name,
    :gravatar_url, :referral_url,
    to: :decorator

  mount_uploader :uploaded_image, UserUploader, mount_on: :uploaded_image

  validates_length_of :bio, maximum: 140
  validates_presence_of :email
  validates_uniqueness_of :email, :allow_blank => true, :if => :email_changed?, :message => I18n.t('activerecord.errors.models.user.attributes.email.taken')
  validates_format_of :email, :with => Devise.email_regexp, :allow_blank => true, :if => :email_changed?

  validates_presence_of :password, if: :password_required?
  validates_confirmation_of :password, if: :password_confirmation_required?
  validates_length_of :password, :within => Devise.password_length, :allow_blank => true

  belongs_to :referrer, class_name: 'User', foreign_key: 'referrer_id'
  has_many :contributions
  has_many :projects
  has_many :notifications
  has_many :authorizations
  has_many :oauth_providers, through: :authorizations
  has_one :organization, dependent: :destroy
  has_and_belongs_to_many :recommended_projects, join_table: :recommendations, class_name: 'Project'
  has_one :investment_prospect, dependent: :destroy

  accepts_nested_attributes_for :authorizations
  accepts_nested_attributes_for :organization
  accepts_nested_attributes_for :investment_prospect

  pg_search_scope :pg_search, against: [
      [:name,  'A'],
      [:email, 'B'],
      [:bio,   'C'],
      [:id,    'D']
    ],
    associated_against: {
      organization: %i(name)
    },
    using: {
      tsearch: {
        dictionary: 'english'
      }
    },
    ignoring: :accents

  scope :who_contributed_project, ->(project_id) {
    where("id IN (SELECT user_id FROM contributions WHERE contributions.state = 'confirmed' AND project_id = ?)", project_id)
  }

  state_machine :profile_type, initial: :personal do
    state :personal, value: 'personal'
    state :organization, value: 'organization'
  end

  def decorator
    @decorator ||= UserDecorator.new(self)
  end

  def total_contributed_projects
    contributions.count('distinct project_id')
  end

  def facebook_id
    auth = authorizations.joins(:oauth_provider).where("oauth_providers.name = 'facebook'").first
    auth.uid if auth
  end

  def to_param
    return "#{self.id}" unless self.display_name
    "#{self.id}-#{self.display_name.parameterize}"
  end

  def total_contributions
    contributions.with_state('confirmed').not_anonymous.count
  end

  def projects_led
    projects.visible.not_soon
  end

  def total_led
    projects_led.count
  end

  def password_required?
    if bonds_early_adopter?
      persisted?
    else
      new_record? || password.present? || password_confirmation.present?
    end
  end

  def password_confirmation_required?
    persisted?
  end

  def confirmation_required?
    !confirmed? and not (authorizations.first and authorizations.first.oauth_provider == OauthProvider.where(name: 'facebook').first)
  end
end
