class Admin::BaseController < ApplicationController
  include AdminAuthentication
  skip_before_action :require_authentication

  layout "admin"
end
