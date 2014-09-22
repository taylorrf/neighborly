class ContributionPolicy < ApplicationPolicy

  self::UserScope = Struct.new(:current_user, :user, :scope) do
    def resolve
      if current_user.try(:admin?)
        scope.available_to_display
      elsif current_user == user
        scope.with_state('confirmed')
      else
        scope.not_anonymous.with_state('confirmed')
      end
    end
  end

  def create?
    done_by_owner_or_admin? && record.project.online?
  end

  def update?
    done_by_owner_or_admin?
  end

  def show?
    done_by_owner_or_admin?
  end

  def pendent?
    change_state? && record.can_pendent?
  end

  def confirm?
    change_state? && record.can_confirm?
  end

  def cancel?
    change_state? && record.can_cancel?
  end

  def refund?
    change_state?
  end

  def hide?
    change_state? && record.can_hide?
  end

  def destroy?
    change_state? && record.can_push_to_trash?
  end

  def permitted_attributes
    {contribution: record.attribute_names.map(&:to_sym) - %i[user_attributes
                                                             user_id
                                                             state
                                                             user
                                                             payment_service_fee
                                                             payment_id]}
  end

  protected

  def change_state?
    user.present? && (user.admin?)
  end
end
