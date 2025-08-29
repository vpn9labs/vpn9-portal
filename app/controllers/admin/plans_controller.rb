class Admin::PlansController < Admin::BaseController
  before_action :set_plan, only: [ :show, :edit, :update, :destroy ]

  def index
    @plans = Plan.all.order(:price)
  end

  def show
  end

  def new
    @plan = Plan.new
  end

  def create
    @plan = Plan.new(plan_params)
    if @plan.save
      redirect_to admin_plans_path, notice: "Plan was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @plan.update(plan_params)
      redirect_to admin_plans_path, notice: "Plan was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @plan.subscriptions.exists?
      redirect_to admin_plans_path, alert: "Cannot delete plan with active subscriptions."
    else
      @plan.destroy
      redirect_to admin_plans_path, notice: "Plan was successfully deleted."
    end
  end

  private

  def set_plan
    @plan = Plan.find(params[:id])
  end

  def plan_params
    params.require(:plan).permit(:name, :price, :currency, :duration_days, :device_limit, :active, :description, :lifetime)
  end
end
