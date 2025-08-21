# Ensure build info is optionally loaded (do not require file during build/precompile)
require Rails.root.join("app/services/build_info")

BuildInfo.current