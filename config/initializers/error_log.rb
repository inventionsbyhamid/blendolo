# Errors the app reports with Rails.error (the provider jobs report what they rescue) go to the production log.
Rails.application.config.after_initialize { Rails.error.subscribe(ErrorLog.new) } if Rails.env.production?
