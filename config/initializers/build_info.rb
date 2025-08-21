# Ensure build info is loaded at runtime, but skip requirement during assets precompile
require Rails.root.join("app/services/build_info")

if defined?(Rake) && Rake.respond_to?(:application) &&
    (app = Rake.application) && app.respond_to?(:top_level_tasks) &&
    app.top_level_tasks.any? { |t| t.start_with?("assets") }
  BuildInfo.load!(require_file: false)
else
  BuildInfo.current
end
