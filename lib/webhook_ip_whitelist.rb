class WebhookIPWhitelist
  ALLOWED_IPS = ENV["BITCART_WEBHOOK_IPS"]&.split(",") || []

  def initialize(app)
    @app = app
  end

  def call(env)
    if protects_path?(env) && ALLOWED_IPS.any?
      remote_ip = env["REMOTE_ADDR"] || env["action_dispatch.remote_ip"].to_s
      unless ALLOWED_IPS.include?(remote_ip)
        return [ 403, {}, [ "Forbidden" ] ]
      end
    end
    @app.call(env)
  end

  private

  def protects_path?(env)
    path = env["PATH_INFO"] || ""
    # Protect the payments webhook endpoint
    path == "/payments/webhook"
  end
end
