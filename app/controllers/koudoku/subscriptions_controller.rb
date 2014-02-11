module Koudoku
  class SubscriptionsController < ApplicationController
    before_filter :load_owner
    before_filter :show_existing_subscription, only: [:index, :new, :create], unless: :no_owner?
    before_filter :load_subscription, only: [:show, :cancel, :edit, :update]
    before_filter :load_plans, only: [:index, :edit]

    def load_plans
      @plans = ::Plan.order(:price)
    end

    def unauthorized
      render status: 401, template: "koudoku/subscriptions/unauthorized"
      false
    end

    def load_owner
      unless params[:owner_id].nil?
        if current_owner.try(:id) == params[:owner_id].try(:to_i)
          @owner = current_owner
        else
          return unauthorized
        end
      end
    end

    def no_owner?
      @owner.nil?
    end

    def load_subscription
      ownership_attribute = (Koudoku.subscriptions_owned_by.to_s + "_id").to_sym
      @subscription = ::Subscription.where(ownership_attribute => current_owner.id).find_by_id(params[:id])
      return @subscription.present? ? @subscription : unauthorized
    end

    # the following two methods allow us to show the pricing table before someone has an account.
    # by default these support devise, but they can be overriden to support others.
    def current_owner
      # e.g. "self.current_user"
      send "current_#{Koudoku.subscriptions_owned_by.to_s}"
    end

    def redirect_to_sign_up
      session["#{Koudoku.subscriptions_owned_by.to_s}_return_to"] = new_subscription_path(plan: params[:plan])
      redirect_to new_registration_path(Koudoku.subscriptions_owned_by.to_s)
    end

    def index

      # don't bother showing the index if they've already got a subscription.
      if current_owner and current_owner.subscription.present?
        redirect_to koudoku.edit_owner_subscription_path(current_owner, current_owner.subscription)
      end

      # Load all plans.
      @plans = ::Plan.order(:display_order).all
      
      # Don't prep a subscription unless a user is authenticated.
      unless no_owner?
        # we should also set the owner of the subscription here.
        @subscription = ::Subscription.new({Koudoku.owner_id_sym => @owner.id})
        # e.g. @subscription.user = @owner
        @subscription.send Koudoku.owner_assignment_sym, @owner
      end

    end

    def new
      if no_owner?

        if defined?(Devise)

          # by default these methods support devise.
          if current_owner
            redirect_to new_owner_subscription_path(current_owner, plan: params[:plan])
          else
            redirect_to_sign_up
          end
          
        else
          raise "This feature depends on Devise for authentication."
        end

      else
        @subscription = ::Subscription.new
        @subscription.plan = ::Plan.find(params[:plan])
      end
    end

    def show_existing_subscription
      if @owner.subscription.present?
        redirect_to owner_subscription_path(@owner, @owner.subscription)
      end
    end

    def create
      begin
        @subscription = ::Subscription.new(subscription_params)
        @subscription.user = @owner
        if @subscription.save
          flash[:notice] = "You've been successfully upgraded."
          redirect_to owner_subscription_path(@owner, @subscription)
        else
          flash[:error] = 'There was a problem processing this transaction.'
          render :new
        end
      rescue => e
        flash[:error] = e.message
        redirect_to edit_owner_subscription_path(@owner, @subscription, update: 'card')
      end   
    end

    def show
      if not ::Subscription.find(params[:id]).coupon == ""
        @current_stripe_id = ::Subscription.find(params[:id]).stripe_id
        if Stripe::Customer.retrieve(@current_stripe_id).discount
          @current_coupon = Stripe::Customer.retrieve(@current_stripe_id).discount.coupon
          if @current_coupon.percent_off
            if @current_coupon.duration == "repeating"
              @coupon_message = "#{@current_coupon.percent_off}% off for the first #{@current_coupon.duration_in_months} months."
            elsif @current_coupon.duration == "once"
              @coupon_message = "#{@current_coupon.percent_off}% off for the first month."
            elsif @current_coupon.duration == "forever"
              @coupon_message = "#{@current_coupon.percent_off}% off."
            end
          elsif @current_coupon.amount_off
            if @current_coupon.duration == "repeating"
              @coupon_message = "$#{@current_coupon.amount_off/100} off for the first #{@current_coupon.duration_in_months} months."
            elsif @current_coupon.duration == "once"
              @coupon_message = "$#{@current_coupon.amount_off/100} off for the first month."
            elsif @current_coupon.duration == "forever"
              @coupon_message = "$#{@current_coupon.amount_off/100} off."
            end
          end
        end
      end
    end

    def cancel
      flash[:notice] = "You've successfully cancelled your subscription."
      @subscription.plan_id = nil
      @subscription.save
      redirect_to owner_subscription_path(@owner, @subscription)
    end

    def edit
      if not ::Subscription.find(params[:id]).coupon == ""
        @current_stripe_id = ::Subscription.find(params[:id]).stripe_id
        if Stripe::Customer.retrieve(@current_stripe_id).discount
          @current_coupon = Stripe::Customer.retrieve(@current_stripe_id).discount.coupon
          if @current_coupon.percent_off
            if @current_coupon.duration == "repeating"
              @coupon_message = "#{@current_coupon.percent_off}% off for the first #{@current_coupon.duration_in_months} months."
            elsif @current_coupon.duration == "once"
              @coupon_message = "#{@current_coupon.percent_off}% off for the first month."
            elsif @current_coupon.duration == "forever"
              @coupon_message = "#{@current_coupon.percent_off}% off."
            end
          elsif @current_coupon.amount_off
            if @current_coupon.duration == "repeating"
              @coupon_message = "$#{@current_coupon.amount_off/100} off for the first #{@current_coupon.duration_in_months} months."
            elsif @current_coupon.duration == "once"
              @coupon_message = "$#{@current_coupon.amount_off/100} off for the first month."
            elsif @current_coupon.duration == "forever"
              @coupon_message = "$#{@current_coupon.amount_off/100} off."
            end
          end
        end
      end
    end

    def update
      begin
        if @subscription.update_attributes(subscription_params)
          flash[:notice] = "You've successfully updated your subscription."
          redirect_to owner_subscription_path(@owner, @subscription)
        else
          flash[:error] = 'There was a problem processing this transaction.'
          redirect_to edit_owner_subscription_path(@owner, @subscription, update: 'card')
        end
      rescue => e
        flash[:error] = e.message
        redirect_to edit_owner_subscription_path(@owner, @subscription, update: 'card')
      end

    end

    private
    def subscription_params
      
      # If strong_parameters is around, use that.
      if defined?(ActionController::StrongParameters)
        params.require(:subscription).permit(:plan_id, :stripe_id, :current_price, :credit_card_token, :card_type, :last_four, :coupon_code)
      else
        # Otherwise, let's hope they're using attr_accessible to protect their models!
        params[:subscription]
      end

    end
  end
end