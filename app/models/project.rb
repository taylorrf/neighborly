class Project < ActiveRecord::Base
  extend  CatarseAutoHtml
  include ActionView::Helpers::TextHelper,
          PgSearch,
          Taggable,
          Shared::StateMachineHelpers,
          Project::StateMachineHandler,
          Project::VideoHandler,
          Project::CustomValidators,
          Project::OrganizationType,
          Shared::LocationHandler,
          Shared::Notifiable

  mount_uploader :uploaded_image, ProjectUploader, mount_on: :uploaded_image
  mount_uploader :hero_image, HeroImageUploader, mount_on: :hero_image
  has_permalink  :name, true

  delegate :display_status,
           :display_image,
           :display_expires_at,
           :remaining_text,
           :time_to_go,
           :display_pledged,
           :display_goal,
           :remaining_days,
           :progress_bar,
           :display_address_formated,
           :display_organization_type,
           :display_tax_exempt_yield,
           :rating_description,
           :maturity_period,
           to: :decorator

  enum credit_type: %i(general_obligation revenue)
  enum rating:      %i(AAA AA+ AA AA- A+ A A- BBB+ BBB BBB- BB+ BB BB- B+ B B-)

  belongs_to :user
  belongs_to :category
  has_one :project_total
  has_many :contributions, dependent: :destroy
  has_many :rewards, dependent: :destroy
  has_many :project_faqs, dependent: :destroy
  has_many :project_documents, dependent: :destroy
  has_many :activities, dependent: :destroy

  accepts_nested_attributes_for :rewards
  accepts_nested_attributes_for :project_documents

  delegate :pledged, :progress, :total_contributions,
    :total_payment_service_fee, to: :project_total

  catarse_auto_html_for field: :summary, video_width: 720, video_height: 405
  catarse_auto_html_for field: :budget, video_width: 720, video_height: 405
  catarse_auto_html_for field: :terms, video_width: 720, video_height: 405

  pg_search_scope :pg_search, against: [
      [:name,     'A'],
      [:headline, 'B'],
      [:summary,  'C']
    ],
    associated_against: {
      user: %i(name email address_city),
      category: %i(name_en name_pt)
    },
    using: {
      tsearch: {
        dictionary: 'english'
      }
    },
    ignoring: :accents

  # Used to simplify a has_scope
  scope :active, ->{ with_state('online') }
  scope :successful, ->{ with_state('successful') }
  scope :by_id, ->(id) { where(id: id) }
  scope :find_by_permalink!, ->(p) { without_state('deleted').where("lower(permalink) = lower(?)", p).first! }
  scope :user_name_contains, ->(term) { joins(:user).where("unaccent(upper(users.name)) LIKE ('%'||unaccent(upper(?))||'%')", term) }
  scope :by_permalink, ->(p) { without_state('deleted').where("lower(permalink) = lower(?)", p) }
  scope :to_finish, ->{ expired.with_states(['online', 'waiting_funds']) }
  scope :visible, -> { without_states(['draft', 'rejected', 'deleted']) }
  scope :recommended, -> { where(recommended: true) }
  scope :expired, -> { where("projects.expires_at < current_timestamp") }
  scope :not_expired, -> { where("projects.expires_at >= current_timestamp") }
  scope :expiring, -> { not_expired.where("projects.expires_at <= (current_timestamp + interval '2 weeks')") }
  scope :not_expiring, -> { not_expired.where("NOT (projects.expires_at <= (current_timestamp + interval '2 weeks'))") }
  scope :recent, -> { where("(current_timestamp - projects.sale_date) <= '5 days'::interval") }
  scope :soon, -> { with_state('soon').where('uploaded_image IS NOT NULL') }
  scope :not_soon, -> { where("projects.state NOT IN ('soon')") }
  scope :order_for_search, ->{ reorder("
                                     CASE projects.state
                                     WHEN 'online' THEN 1
                                     WHEN 'waiting_funds' THEN 2
                                     WHEN 'successful' THEN 3
                                     END ASC, projects.sale_date DESC, projects.created_at DESC") }

  scope :contributed_by, ->(user_id){
    where("id IN (SELECT project_id FROM contributions b WHERE b.state = 'confirmed' AND b.user_id = ?)", user_id)
  }

  scope :with_contributions_confirmed_today, -> {
    joins(:contributions).merge(Contribution.confirmed_today).uniq
  }

  scope :order_by, ->(sort_field) do
    order(sort_field) if sort_field =~ /^\w+(\.\w+)?\s(desc|asc)$/i
  end

  validates :online_days, :address_city, :address_state, presence: true, if: ->(p) { p.state_name == 'online' }
  validates_presence_of :name, :user, :category, :summary, :headline, :goal, :permalink, :location, :statement_file_url, :minimum_investment
  validates_length_of :headline, maximum: 140
  validates_numericality_of :online_days
  validates_uniqueness_of :permalink, allow_blank: true, case_sensitive: false, on: :update
  validates_format_of :permalink, with: /\A(\w|-)*\z/, allow_blank: true
  validates_format_of :video_url, with: /(https?\:\/\/|)(youtu(\.be|be\.com)|vimeo).*+/, message: I18n.t('project.video_regex_validation'), allow_blank: true

  before_validation do
    if self.site.present?
      self.site = "http://#{self.site}" if not self.site[0..6] == 'http://' and not self.site[0..7] == 'https://'
    end
  end

  def self.between_created_at(start_at, ends_at)
    return all unless start_at.present? && ends_at.present?
    where("created_at between to_date(?, 'dd/mm/yyyy') and to_date(?, 'dd/mm/yyyy')", start_at, ends_at)
  end

  def subscribed_users
    User.subscribed_to_updates.subscribed_to_project(self.id)
  end

  def decorator
    @decorator ||= ProjectDecorator.new(self)
  end

  def expires_at
    sale_date && (sale_date + online_days.days).end_of_day
  end

  def selected_rewards
    rewards.sort_asc.where(id: contributions.with_state('confirmed').map(&:reward_id))
  end

  def reached_goal?
    pledged >= goal
  end

  def expired?
    expires_at && expires_at < Time.zone.now
  end

  def in_time_to_wait?
    contributions.with_state('waiting_confirmation').count > 0
  end

  def pending_contributions_reached_the_goal?
    pledged_and_waiting >= goal
  end

  def pledged_and_waiting
    contributions.with_states(['confirmed', 'waiting_confirmation']).sum(:value)
  end

  def new_draft_recipient
    email = ::Configuration[:email_projects]
    User.where(email: email).first
  end

  def notification_type type
    type
  end

  def self.locations
    visible.select('DISTINCT address_city, address_state').order('address_city, address_state').map(&:location)
  end

  private
  def self.get_routes
    routes = Rails.application.routes.routes.map do |r|
      r.path.spec.to_s.split('/').second.to_s.gsub(/\(.*?\)/, '')
    end
    routes.compact.uniq
  end
end
