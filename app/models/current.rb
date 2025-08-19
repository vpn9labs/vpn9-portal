class Current < ActiveSupport::CurrentAttributes
  attribute :session, :admin_session
  delegate :user, to: :session, allow_nil: true
  delegate :admin, to: :admin_session, allow_nil: true
end
